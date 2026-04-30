public with sharing class NewsAPIInvoker {

    // Input structure
    public class NewsRequest {
        @InvocableVariable(required=true)
        public String category;

        @InvocableVariable(required=false)
        public String query;

        @InvocableVariable(required=true)
        public String apiKey;
    }

    // Output structure
    public class NewsResponse {
        @InvocableVariable
        public String newsResults;
    }

    @InvocableMethod(label='Get News from API' description='Fetch news based on category and optional query')
    public static List<NewsResponse> getNews(List<NewsRequest> requests) {
        List<NewsResponse> responses = new List<NewsResponse>();

        for (NewsRequest req : requests) {
            NewsResponse res = new NewsResponse();

            try {
                // Base endpoint
                String endpoint = 'https://newsapi.org/v2/top-headlines?';

                List<String> params = new List<String>();

                // Mandatory params
                //params.add('apiKey=' + EncodingUtil.urlEncode(req.apiKey, 'UTF-8'));
                params.add('apiKey=' + '3dfc1afb2f9e429098187d548ac1d42f');
                params.add('category=' + EncodingUtil.urlEncode(req.category, 'UTF-8'));
                params.add('category=' + 'finance+market+business');
                params.add('page=1');

                // Optional query param
                if (String.isNotBlank(req.query)) {
                    params.add('q=' + EncodingUtil.urlEncode(req.query, 'UTF-8'));
                }

                // Join parameters
                endpoint += String.join(params, '&');

                Http http = new Http();
                HttpRequest httpReq = new HttpRequest();
                httpReq.setEndpoint(endpoint);
                httpReq.setMethod('GET');
                httpReq.setHeader('Content-Type', 'application/json');

                HttpResponse httpRes = http.send(httpReq);

                if (httpRes.getStatusCode() == 200) {
                    res.newsResults = httpRes.getBody();
                } else {
                    res.newsResults = JSON.serialize(
                        new Map<String, Object>{
                            'error' => 'API Error',
                            'statusCode' => httpRes.getStatusCode(),
                            'body' => httpRes.getBody()
                        }
                    );
                }

            } catch (Exception e) {
                res.newsResults = JSON.serialize(
                    new Map<String, Object>{
                        'error' => 'Exception occurred',
                        'message' => e.getMessage()
                    }
                );
            }

            responses.add(res);
        }

        return responses;
    }
}