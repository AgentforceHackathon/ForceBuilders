public with sharing class MarketeventupdateToIngestionAPICall {

    public class Request {
        @InvocableVariable(required=true label='marketevent')
        public marketevents__c record;
    }

    public class Response {
        @InvocableVariable(label='Result')
        public String result;

        @InvocableVariable(label='Message')
        public String message;
    }
	
    @InvocableMethod(
        label='Process News To Market Events'
        description='Calls NewsAPIInvoker, sends JSON to prompt template, parses returned JSON array, and creates/updates MarketEvents__c records.'
    )
    public static List<Response> sendIngestionAPICall(List<Request> requests) {
        List<Response> resList=new List<Response>();
        Response res=new Response();
        List<Map<String, Object>> inputList = new List<Map<String, Object>>();
        for (Request req : requests) {
            MarketEvents__c rec = req.record;
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
               try {
                        MarketEvent_IngestionAPI_Callout.ingestDataAsync(
                            'IngestMarketNews',
                            'NewsItem',
                            JSON.serialize(inputList)
                        );
                        System.debug('Ingestion callout dispatched for records.');
                   		res.result='Success';
                        res.message = 'Successfully posted';
                        resList.add(res);
                    } catch (Exception e) {
                        // Log but do NOT fail the whole transaction —
                        // DML already succeeded; ingestion can be retried separately
                        System.debug('WARNING: Ingestion dispatch failed: ' + e.getMessage());
                        res.result='Failed';
                        res.message = 'WARNING: Ingestion API dispatch failed for id'+ String.valueOf(rec.Id);
                        resList.add(res);
                    }

        }
        return resList;
    }
}