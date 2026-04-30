public without sharing class WhatsAppService {

    // Send regular text message
    public static void sendWhatsAppMessage(String toNumber, String messageBody) {
        try {
            System.debug('========== WhatsApp Send ==========');

            // Create HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:WhatsappNC/Messages.json'); // Named Credential
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            //  sandbox / WhatsApp number
            String fromNumber = 'whatsapp:+14155238886';

            // Ensure proper WhatsApp format
            String formattedToNumber = toNumber.startsWith('whatsapp:')
                ? toNumber
                : 'whatsapp:' + toNumber;

            // Build payload
            String payload = 'From=' + EncodingUtil.urlEncode(fromNumber, 'UTF-8')
                + '&To=' + EncodingUtil.urlEncode(formattedToNumber, 'UTF-8')
                + '&Body=' + EncodingUtil.urlEncode(messageBody, 'UTF-8');

            req.setBody(payload);

            // Send request
            Http http = new Http();
            HttpResponse res = http.send(req);

            System.debug('Response: ' + res.getStatusCode() + ' - ' + res.getBody());

        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
        }
    }
}