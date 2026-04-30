public without sharing class ImapctedAccountSectorwiseToday {

    /*
     PERFORMANCE FIX:
     ----------------
     Heavy DML (insert + update) moved to ASYNC Queueable

     FLOW:
     1. Read Calculated Insight
     2. If no records found -> AdvisoryGenerated = N
     3. Build summary for Agentforce
     4. Build marketing news string
     5. Prepare impacted account records
     6. Call Queueable for async insert/update
     7. Return response immediately to Agentforce

     BENEFIT:
     --------
     - Faster Flow execution
     - No timeout issue
     - No DML performance bottleneck
     - Better scalability
    */

    public class Result {

        @InvocableVariable(
            description='Summary of impacted customer accounts for Agentforce'
        )
        public String summary;

        @InvocableVariable(
            description='Advisory Generated Flag (Y/N)'
        )
        public String advisoryGenerated;

        @InvocableVariable(
            description='Marketing News passed to Agentforce'
        )
        public String marketingNews;
    }

    public class Request {

        @InvocableVariable(
            description='Optional Account Id filter'
        )
        public String accountId;
    }

    @InvocableMethod(
        label='Get Sector Impact Summary for Today'
        description='Returns impacted customer summary + creates impacted account records asynchronously'
    )
    public static List<Result> getSectorImpactSummary(
        List<Request> requests
    ) {

        List<Result> outputResults = new List<Result>();

        String ciName = 'AffectedAccounts_Today_Sectorwise2__cio';

        String finalSummary = '';
        String marketingNewsString = '';
        String advisoryGenerated = 'N';

        /*
        ============================================================
        STEP 1: READ CALCULATED INSIGHT
        ============================================================
        */

        ConnectApi.CdpQueryOutput output =
            ConnectApi.CdpQuery.queryCalculatedInsights(
                ciName,
                null,
                null,
                null,
                null,
                200,
                null
            );

        List<Object> results = output.data;

        System.debug('Total CI Records Returned: ' + results.size());

        /*
        ============================================================
        STEP 2: CHECK IF RECORDS FOUND
        ============================================================
        */

        if (results == null || results.isEmpty()) {

            Result noDataResult = new Result();
            noDataResult.summary =
                'No impacted customer accounts found for today.';
            noDataResult.advisoryGenerated = 'N';
            noDataResult.marketingNews =
                'No marketing news available for today.';

            outputResults.add(noDataResult);

            return outputResults;
        }

        advisoryGenerated = 'Y';

        /*
        ============================================================
        STEP 3: PREPARE RECORDS
        ============================================================
        */

        List<Market_Event_Impacted_Account__c> impactedRecords =
            new List<Market_Event_Impacted_Account__c>();

        for (Object o : results) {

            String jsonStr = JSON.serialize(o);

            Map<String, Object> insight =
                (Map<String, Object>) JSON.deserializeUntyped(jsonStr);

            String accountId =
                String.valueOf(insight.get('AccountId__c'));

            String accountName =
                String.valueOf(insight.get('AccountName__c'));

            String sector =
                String.valueOf(insight.get('Sector__c'));

            String holdingCount =
                String.valueOf(insight.get('HoldingCount__c'));

            String newsCount =
                String.valueOf(insight.get('NewsCount__c'));

            String marketingEventId =
                String.valueOf(insight.get('MarketingEventId__c'));

            String riskOppFlag =
                String.valueOf(insight.get('RiskOppFlag__c'));

            String integrationId =
                String.valueOf(insight.get('InteractionId__c'));

            String marketNews =
                String.valueOf(insight.get('MarketNews__c'));

            if (String.isBlank(marketNews)) {
                marketNews =
                    'Sector movement observed based on today market events.';
            }

            /*
            ============================================================
            STEP 4: BUILD SUMMARY
            ============================================================
            */

            finalSummary +=
                'Customer: ' + accountName +
                ' | Sector: ' + sector +
                ' | Risk/Opp: ' + riskOppFlag +
                '\n';

            /*
            ============================================================
            STEP 5: BUILD MARKETING NEWS
            ============================================================
            */

            marketingNewsString +=
                'Customer: ' + accountName +
                ' | Marketing News: ' + marketNews +
                '\n';

            /*
            ============================================================
            STEP 6: PREPARE IMPACTED RECORD
            ============================================================
            */

            Market_Event_Impacted_Account__c rec =
                new Market_Event_Impacted_Account__c();

            rec.Account__c = accountId;
            rec.Advisory_Message__c = marketNews;
            rec.Communication_Channel__c = 'Email';
            rec.Date_Time__c = System.now();

            if (String.isNotBlank(integrationId)
    && integrationId != 'null') {

    rec.InteractionId__c =
        Integer.valueOf(
            String.valueOf(
                Decimal.valueOf(integrationId)
            )
            .split('\\.')[0]
        );
}
            

            rec.Market_Event__c = marketingEventId;
            rec.Picked_Status__c = 'Not Picked';
            rec.ProcessedFlag__c = 'New';

            impactedRecords.add(rec);
        }

        /*
        ============================================================
        STEP 7: ASYNC PROCESS (Queueable)
        ============================================================
        */

        if (!impactedRecords.isEmpty()) {
            System.enqueueJob(
                new ImpactedAccountAsyncProcessor(impactedRecords)
            );
        }

        /*
        ============================================================
        STEP 8: RETURN TO AGENTFORCE IMMEDIATELY
        ============================================================
        */

        Result r = new Result();
        r.summary = finalSummary;
        r.advisoryGenerated = advisoryGenerated;
        r.marketingNews = marketingNewsString;

        outputResults.add(r);

        return outputResults;
    }
}