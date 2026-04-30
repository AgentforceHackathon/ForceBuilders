public class MarketEvent_IngestionAPI_Callout {

    // Named Credential pointing to your Data Cloud tenant base URL
    // e.g. https://<tenant>.c360a.salesforce.com
    // No authentication configured on this Named Credential — we pass the Bearer token ourselves
    private static final String DC360_NC = 'callout:DC_IngestionAPI_NC';

    // -------------------------------------------------------------------------
    // STEP 1: Exchange the current session's access token for a Data 360 token
    // No client_id / client_secret needed — we reuse the running user's session
    // -------------------------------------------------------------------------
    private static Data360TokenWrapper getAccessToken() {
        // UserInfo.getSessionId() gives us the Salesforce access token for the current user
        // This works as the subject_token for the a360 token exchange on the home org
        
        //String orgDomainUrl = Url.getOrgDomainUrl().toExternalForm();

        HttpRequest req = new HttpRequest();
        // Token exchange endpoint uses the org's own My Domain URL
        String param=
            'grant_type=' + EncodingUtil.urlEncode('client_credentials', 'UTF-8')
            + '&client_id=' + EncodingUtil.urlEncode('3MVG91oqviqJKoEHNQZK9CV_ZhdE0PcqhBGmAkG4tUBof0YDEpDfeVs_jWik5HMV7EVe0oY9N9HvRXXBFzNuE', 'UTF-8')
            + '&client_secret=' + EncodingUtil.urlEncode('F3AE96927BCE0DADCFBB62947BFC47F6497587E076255A6E8FE9342043E24DA7', 'UTF-8');

        req.setEndpoint('https://orgfarm-2a4bc1e9a6.my.salesforce.com/services/oauth2/token?'+param);
        req.setMethod('GET');
//        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
      
        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Data360TokenWrapper wrapper = new Data360TokenWrapper();
            wrapper.accessToken = (String) body.get('access_token');
            wrapper.instanceUrl = (String) body.get('instance_url');
            System.debug('accessToken '+(String) body.get('instance_url'));
            return wrapper;
        } else {
            throw new CalloutException(
                'Failed to get Data 360 token. Status: ' + res.getStatusCode()
                + ' Body: ' + res.getBody()
            );
        }
    }

    public static Data360TokenWrapper getData360Token() {
        // This works as the subject_token for the a360 token exchange on the home org
        
        //String orgDomainUrl = Url.getOrgDomainUrl().toExternalForm();
		Data360TokenWrapper accessTokenResponse=getAccessToken();
        Data360TokenWrapper data360TokenResponse=new Data360TokenWrapper();
        HttpRequest req = new HttpRequest();
        // Token exchange endpoint uses the org's own My Domain URL
        
        req.setEndpoint('https://orgfarm-2a4bc1e9a6.my.salesforce.com/services/a360/token');
        req.setMethod('POST');
		req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setHeader('Authorization', 'Bearer ' + accessTokenResponse.accessToken);
        req.setBody(
            'grant_type='            + EncodingUtil.urlEncode('urn:salesforce:grant-type:external:cdp', 'UTF-8')
            + '&subject_token='      + EncodingUtil.urlEncode(accessTokenResponse.accessToken, 'UTF-8')
            + '&subject_token_type=' + EncodingUtil.urlEncode('urn:ietf:params:oauth:token-type:access_token', 'UTF-8')
        );
      
        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Data360TokenWrapper wrapper = new Data360TokenWrapper();
            wrapper.accessToken = (String) body.get('access_token');
            wrapper.instanceUrl = (String) body.get('instance_url');
            System.debug('accessToken '+(String) body.get('instance_url'));
            return wrapper;
        } else {
            throw new CalloutException(
                'Failed to get Data 360 token. Status: ' + res.getStatusCode()
                + ' Body: ' + res.getBody()
            );
        }
    }

    
    // -------------------------------------------------------------------------
    // STEP 2: Call the Data 360 Streaming Ingestion API
    // -------------------------------------------------------------------------
    public static void ingestData(String connectorName, String objectName, List<Map<String, Object>> records) {
        // Get the Data 360 token using the current session (no hardcoded secrets)
        Data360TokenWrapper dc360Token = getData360Token();

        
        Map<String, Object> payload = new Map<String, Object>{ 'data' => records };
        String jsonBody = JSON.serialize(payload);
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://gqyds9ddh04dsmb-gvsw8mbqgq.c360a.salesforce.com/api/v1/ingest/sources/'
            + EncodingUtil.urlEncode(connectorName, 'UTF-8')
            + '/'
            + EncodingUtil.urlEncode(objectName, 'UTF-8')
        );
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + dc360Token.accessToken);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonBody);

        Http http = new Http();
        HttpResponse res = http.send(req);

        // Ingestion API returns 202 Accepted on success
        if (res.getStatusCode() == 202) {
            System.debug('Ingestion successful: ' + res.getBody());
        } else {
            throw new CalloutException(
                'Ingestion failed. Status: ' + res.getStatusCode()
                + ' Body: ' + res.getBody()
            );
        }
    }

    // -------------------------------------------------------------------------
    // If calling from a trigger or context where callouts aren't allowed,
    // wrap in a @future method
    // -------------------------------------------------------------------------
    @future(callout=true)
    public static void ingestDataAsync(String connectorName, String objectName, String recordsJson) {
        List<Object> rawList = (List<Object>) JSON.deserializeUntyped(recordsJson);
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        for (Object o : rawList) {
            records.add((Map<String, Object>) o);
        }
        ingestData(connectorName, objectName, records);
    }

    // Inner class for token response
    public class Data360TokenWrapper {
        public String accessToken;
        public String instanceUrl;
    }
}