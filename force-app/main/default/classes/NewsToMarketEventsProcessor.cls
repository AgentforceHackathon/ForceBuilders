public with sharing class NewsToMarketEventsProcessor {

    public class Request {
        @InvocableVariable(required=true label='Category')
        public String category;

        @InvocableVariable(required=false label='Query')
        public String query;
    }

    public class Response {
        @InvocableVariable(label='News JSON')
        public String newsJson;

        @InvocableVariable(label='Prompt Output')
        public String promptOutput;

        @InvocableVariable(label='Inserted Record Count')
        public Integer insertedRecordCount;

        @InvocableVariable(label='Updated Record Count')
        public Integer updatedRecordCount;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Message')
        public String message;
    }

    public class ProcessorException extends Exception {}

    public interface PromptTemplateService {
        String generatePromptResponse(String jsonInput);
    }

    public class DefaultPromptTemplateService implements PromptTemplateService {
        public String generatePromptResponse(String jsonInput) {
            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();

            Map<String, ConnectApi.WrappedValue> inputParams =
                new Map<String, ConnectApi.WrappedValue>();
            ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
            wrappedValue.value = jsonInput;
            inputParams.put('Input:news', wrappedValue);

            ConnectApi.EinsteinPromptTemplateGenerationsInput executeTemplateInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            executeTemplateInput.additionalConfig =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            executeTemplateInput.additionalConfig.applicationName = 'PromptBuilderPreview';
            executeTemplateInput.isPreview = false;
            executeTemplateInput.inputParams = inputParams;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation promptTemplateResult = null;
            try {
                promptTemplateResult = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    'NewsClassifier',
                    executeTemplateInput
                );
            } catch (Exception e) {
                System.debug('Error message is ' + e.getMessage());
                throw e;
            }

            if (promptTemplateResult == null
                || promptTemplateResult.generations == null
                || promptTemplateResult.generations.isEmpty()) {
                throw new ProcessorException('Prompt template returned no output.');
            }

            if (String.isBlank(promptTemplateResult.generations[0].text)) {
                throw new ProcessorException('Prompt template returned blank output.');
            }

            return promptTemplateResult.generations[0].text;
        }
    }

    @TestVisible
    private static PromptTemplateService promptService = new DefaultPromptTemplateService();

    @InvocableMethod(
        label='Process News To Market Events'
        description='Calls NewsAPIInvoker, sends JSON to prompt template, parses returned JSON array, and creates/updates MarketEvents__c records.'
    )
    public static List<Response> processNews(List<Request> requests) {
        List<Response> responseList = new List<Response>();

        if (requests == null || requests.isEmpty()) {
            return responseList;
        }

        for (Request req : requests) {
            Response res = new Response();
            res.insertedRecordCount = 0;
            res.updatedRecordCount  = 0;

            try {
                validateRequest(req);
                System.debug('1');

                NewsAPIInvoker.NewsRequest newsReq = new NewsAPIInvoker.NewsRequest();
                newsReq.category = req.category;
                if (!String.isBlank(req.query)) {
                    newsReq.query = req.query;
                }
                newsReq.apiKey = '3dfc1afb2f9e429098187d548ac1d42f';

                List<NewsAPIInvoker.NewsResponse> newsResponses =
                    NewsAPIInvoker.getNews(
                        new List<NewsAPIInvoker.NewsRequest>{ newsReq }
                    );

                if (newsResponses == null
                    || newsResponses.isEmpty()
                    || String.isBlank(newsResponses[0].newsResults)) {
                    throw new ProcessorException('No response received from NewsAPIInvoker.');
                }

                res.newsJson = newsResponses[0].newsResults;

                Integer totalResults = extractTotalResults(res.newsJson);
                if (totalResults <= 0) {
                    res.status  = 'NO_NEWS';
                    res.message = 'No articles found in News API response.';
                    responseList.add(res);
                    continue;
                }

                res.promptOutput = promptService.generatePromptResponse(res.newsJson);

                List<Object> parsedEvents = extractJsonArray(res.promptOutput);

                if (parsedEvents == null || parsedEvents.isEmpty()) {
                    res.status  = 'NO_EVENTS';
                    res.message = 'Prompt template output did not contain any event records.';
                    responseList.add(res);
                    continue;
                }

                System.debug('2');

                Integer newInteractionId = getNextIntegrationId();
                System.debug('Next IntegrationId is ' + newInteractionId);

                Datetime now = Datetime.now();

                // ---------------------------------------------------------------
                // Collect all IAValues from parsed events to query existing records
                // ---------------------------------------------------------------
                List<String> incomingIAValues = new List<String>();
                List<Map<String, Object>> eventMaps = new List<Map<String, Object>>();

                for (Object obj : parsedEvents) {
                    if (obj instanceof Map<String, Object>) {
                        Map<String, Object> eventMap = (Map<String, Object>) obj;
                        eventMaps.add(eventMap);
                        incomingIAValues.add(getStringValue(eventMap, 'IAValue'));
                    }
                }

                // ---------------------------------------------------------------
                // Fetch today's unprocessed records that match any incoming IAValue
                // Returns a map of IAValue -> existing MarketEvents__c record
                // If 2 records exist for same IAValue, we pick the first one to update
                // (the second duplicate is left untouched — edge case)
                // ---------------------------------------------------------------
                Map<String, MarketEvents__c> existingByIAValue =
                    fetchTodayUnprocessedByIAValues(incomingIAValues);

                // ---------------------------------------------------------------
                // Split into records to UPDATE vs records to INSERT
                // ---------------------------------------------------------------
                List<MarketEvents__c> recordsToUpdate = new List<MarketEvents__c>();
                List<MarketEvents__c> recordsToInsert = new List<MarketEvents__c>();

                for (Map<String, Object> eventMap : eventMaps) {
                    String iaValue = getStringValue(eventMap, 'IAValue');

                    if (existingByIAValue.containsKey(iaValue)) {
                        // --- UPDATE path: reuse same record Id, assign new InteractionId ---
                        MarketEvents__c existing = existingByIAValue.get(iaValue);
                        existing = applyEventFields(existing, eventMap, newInteractionId, now);
                        recordsToUpdate.add(existing);
                        // Remove from map so a second event with same IAValue goes to insert
                        //existingByIAValue.remove(iaValue);
                    } else {
                        // --- INSERT path: brand new record ---
                        MarketEvents__c newRecord = new MarketEvents__c();
                        newRecord = applyEventFields(newRecord, eventMap, newInteractionId, now);
                        recordsToInsert.add(newRecord);
                    }
                }

                // ---------------------------------------------------------------
                // DML — update first, then insert
                // ---------------------------------------------------------------
                if (!recordsToUpdate.isEmpty()) {
                    update recordsToUpdate;
                    res.updatedRecordCount = recordsToUpdate.size();
                    System.debug('Updated ' + recordsToUpdate.size() + ' existing MarketEvents__c records.');
                }

                if (!recordsToInsert.isEmpty()) {
                    insert recordsToInsert;
                    res.insertedRecordCount = recordsToInsert.size();
                    System.debug('Inserted ' + recordsToInsert.size() + ' new MarketEvents__c records.');
                }

                // ----------------------------------------------------------
                // STEP 9: Build Data 360 ingestion payload from DML'd records
                // Combine updated + inserted into one payload list.
                // All records now have a real Salesforce Id (inserts got one post-DML).
                // Callout must happen AFTER DML — dispatched via @future.
                // ----------------------------------------------------------
                List<MarketEvents__c> allProcessedRecords = new List<MarketEvents__c>();
                allProcessedRecords.addAll(recordsToUpdate);
                allProcessedRecords.addAll(recordsToInsert);

                if (!allProcessedRecords.isEmpty()) {
                    String ingestionPayloadJson = buildIngestionPayload(allProcessedRecords);

                    // @future because callouts cannot be made in same transaction as DML
                    try {
                        MarketEvent_IngestionAPI_Callout.ingestDataAsync(
                            'IngestMarketNews',
                            'NewsItem',
                            ingestionPayloadJson
                        );
                        System.debug('Ingestion callout dispatched for '
                            + allProcessedRecords.size() + ' records.');
                    } catch (Exception e) {
                        // Log but do NOT fail the whole transaction —
                        // DML already succeeded; ingestion can be retried separately
                        System.debug('WARNING: Ingestion dispatch failed: ' + e.getMessage());
                        res.message = (String.isBlank(res.message) ? '' : res.message + ' | ')
                            + 'WARNING: Ingestion API dispatch failed: ' + e.getMessage();
                    }
                }

                res.status  = 'SUCCESS';
                res.message = 'MarketEvents__c records processed successfully. '
                    + 'Updated: ' + res.updatedRecordCount
                    + ', Inserted: ' + res.insertedRecordCount + '.';

            } catch (Exception ex) {
                res.status  = 'ERROR';
                res.message = ex.getMessage();
            }

            responseList.add(res);
        }

        return responseList;
    }

    // ---------------------------------------------------------------------------
    // Fetch today's ProcessedFlag=N records matching given IAValues
    // Returns Map<IAValue, MarketEvents__c> — one record per IAValue (first found)
    // If 2 records exist for same IAValue today, only the first is returned for
    // update; the second remains untouched (consistent with your "2 records" rule)
    // ---------------------------------------------------------------------------
    private static Map<String, MarketEvents__c> fetchTodayUnprocessedByIAValues(
        List<String> iaValues
    ) {
        Map<String, MarketEvents__c> resultMap = new Map<String, MarketEvents__c>();

        if (iaValues == null || iaValues.isEmpty()) {
            return resultMap;
        }

        List<MarketEvents__c> existing = [
            SELECT Id,
                   IAValue__c,
                   Title__c,
                   Description__c,
                   Category__c,
                   ConfidenceScore__c,
                   RiskOppFlag__c,
                   ImpactedArea__c,
                   CreatedDateTime__c,
                   ProcessedFlag__c,
                   InteractionId__c
            FROM   MarketEvents__c
            WHERE  IAValue__c IN :iaValues
            AND    DAY_ONLY(CreatedDateTime__c) = :Date.today()
            AND    ProcessedFlag__c = 'N'
            ORDER BY CreatedDateTime__c ASC  // pick earliest record for update
            LIMIT  1000
        ];

        // Build map — first record wins per IAValue (handles the 2-record scenario)
        for (MarketEvents__c rec : existing) {
            if (!resultMap.containsKey(rec.IAValue__c)) {
                resultMap.put(rec.IAValue__c, rec);
            }
        }

        return resultMap;
    }

    
    // ---------------------------------------------------------------------------
    // Apply all event fields to a record (works for both new and existing records)
    // ---------------------------------------------------------------------------
    private static MarketEvents__c applyEventFields(
        MarketEvents__c record,
        Map<String, Object> eventMap,
        Integer interactionId,
        Datetime now
    ) {
        record.Title__c           = getStringValue(eventMap, 'Title');
        record.Description__c     = getStringValue(eventMap, 'Description');
        record.Category__c        = getStringValue(eventMap, 'Category');
        record.ConfidenceScore__c = getStringValue(eventMap, 'ConfidenceScore');
        record.RiskOppFlag__c     = getStringValue(eventMap, 'RiskOppFlag');
        record.ImpactedArea__c    = getStringValue(eventMap, 'ImpactedArea');
        record.IAValue__c         = getStringValue(eventMap, 'IAValue');
        record.CreatedDateTime__c = now;
        record.ProcessedFlag__c   = 'N';
        record.InteractionId__c   = interactionId;
        return record;
    }

    // ---------------------------------------------------------------------------
    // Kept for reference — no longer called, replaced by fetchTodayUnprocessedByIAValues
    // ---------------------------------------------------------------------------
    // public static void deleteTodayUnProcessedRecordsByValues(List<String> filterValues) { ... }

    private static void validateRequest(Request req) {
        if (req == null) {
            throw new ProcessorException('Request cannot be null.');
        }
        if (String.isBlank(req.category)) {
            throw new ProcessorException('Category is required.');
        }
    }

    private static Integer extractTotalResults(String newsJson) {
        Object parsed = JSON.deserializeUntyped(newsJson);

        if (!(parsed instanceof Map<String, Object>)) {
            throw new ProcessorException('News JSON is not a valid JSON object.');
        }

        Map<String, Object> newsMap      = (Map<String, Object>) parsed;
        Object              totalResultsObj = newsMap.get('totalResults');

        if (totalResultsObj == null) {
            return 0;
        }

        if (totalResultsObj instanceof Integer) {
            return (Integer) totalResultsObj;
        } else if (totalResultsObj instanceof Decimal) {
            return ((Decimal) totalResultsObj).intValue();
        } else {
            return Integer.valueOf(String.valueOf(totalResultsObj));
        }
    }

    @TestVisible
    private static List<Object> extractJsonArray(String text) {
        if (String.isBlank(text)) {
            return new List<Object>();
        }

        Integer startIndex = text.indexOf('[');
        Integer endIndex   = text.lastIndexOf(']');

        if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
            return new List<Object>();
        }

        String jsonArrayString = text.substring(startIndex, endIndex + 1);
        Object parsed          = JSON.deserializeUntyped(jsonArrayString);

        if (parsed instanceof List<Object>) {
            return (List<Object>) parsed;
        }

        return new List<Object>();
    }

    // Kept for backward compatibility — now only used internally via applyEventFields
    private static MarketEvents__c buildMarketEvent(
        Map<String, Object> eventMap,
        Integer MaxIntegrationId,
        DateTime now
    ) {
        return applyEventFields(new MarketEvents__c(), eventMap, MaxIntegrationId, now);
    }

    private static Integer getNextIntegrationId() {
        String             query   = 'SELECT MAX(InteractionId__c) maxId FROM MarketEvents__c';
        List<AggregateResult> results = Database.query(query);

        if (!results.isEmpty() && results[0].get('maxId') != null) {
            Integer maxIntegrationId = ((Decimal) results[0].get('maxId')).intValue();
            System.debug('The maximum value is: ' + maxIntegrationId);
            return (maxIntegrationId + 1);
        }
        return 1;
    }

    private static String getStringValue(Map<String, Object> data, String key) {
        if (data == null || !data.containsKey(key) || data.get(key) == null) {
            return null;
        }
        return String.valueOf(data.get(key));
    }
     // =========================================================================
    // BUILD INGESTION PAYLOAD
    // Converts List<MarketEvents__c> → List<Map<String,Object>> matching
    // the shape your Postman / Data 360 schema expects.
    // =========================================================================
    @TestVisible
    public static String buildIngestionPayload(List<MarketEvents__c> records) {
        List<Map<String, Object>> inputList = new List<Map<String, Object>>();
        for (MarketEvents__c rec : records) {
            Map<String, Object> row = new Map<String, Object>{
                // Real Salesforce record Id — available after DML
                'Id'              => String.valueOf(rec.Id),
                'Title'           => rec.Title__c,
                'Description'     => rec.Description__c,
                'Category'        => rec.Category__c,
                'ConfidenceScore' => rec.ConfidenceScore__c,
                'RiskOppFlag'     => rec.RiskOppFlag__c,
                'ImpactedArea'    => rec.ImpactedArea__c,
                'IAValue'         => rec.IAValue__c,
                // Format Datetime → ISO 8601 string for API (e.g. 2026-04-21T10:30:00Z)
                'CreatedDateTime' => rec.CreatedDateTime__c != null
                    ? rec.CreatedDateTime__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                    : null,
                'ProcessedFlag'   => rec.ProcessedFlag__c,
                'InteractionId'   => rec.InteractionId__c,
                'InteractionId_ReferThis' => rec.InteractionId__c
            };
            inputList.add(row);
        }
        return JSON.serialize(inputList);
    }
}