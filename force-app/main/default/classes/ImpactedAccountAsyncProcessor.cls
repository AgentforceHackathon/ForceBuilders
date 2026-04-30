public without sharing class ImpactedAccountAsyncProcessor
    implements Queueable {

    private List<Market_Event_Impacted_Account__c> impactedRecords;

    public ImpactedAccountAsyncProcessor(
        List<Market_Event_Impacted_Account__c> impactedRecords
    ) {
        this.impactedRecords = impactedRecords;
    }

    public void execute(QueueableContext context) {

        /*
        ============================================================
        STEP 1: INSERT IMPACTED ACCOUNT RECORDS
        ============================================================
        */

        if (impactedRecords != null && !impactedRecords.isEmpty()) {
            insert impactedRecords;

            System.debug(
                'Inserted impacted records: ' +
                impactedRecords.size()
            );
        }

        /*
        ============================================================
        STEP 2: UPDATE marketevents__c
        ProcessedFlag__c = Y
        ============================================================
        */

        List<marketevents__c> marketEventsToUpdate = [
            SELECT Id,
                   ProcessedFlag__c
            FROM marketevents__c
            WHERE ProcessedFlag__c = 'N'
        ];

        for (marketevents__c me : marketEventsToUpdate) {
            me.ProcessedFlag__c = 'Y';
        }

        if (!marketEventsToUpdate.isEmpty()) {
            update marketEventsToUpdate;

            System.debug(
                'Updated marketevents__c records: ' +
                marketEventsToUpdate.size()
            );
        }
    }
}