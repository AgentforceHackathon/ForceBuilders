public without sharing class WhatsAppService {

    // Wrapper class for Flow input
    public class WhatsAppRequest {
        @InvocableVariable(required=true)
        public String toNumber;

        @InvocableVariable(required=true)
        public String messageBody;
    }

    @InvocableMethod(
        label='Send WhatsApp Message'
        description='Send WhatsApp message via Twilio'
    )
    public static void sendWhatsAppMessage(List<WhatsAppRequest> requests) {

        for (WhatsAppRequest reqData : requests) {
            try {
                System.debug('========== WhatsApp Send ==========');

                HttpRequest req = new HttpRequest();
                req.setEndpoint('callout:WhatsappNC/Messages.json');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

                String fromNumber = 'whatsapp:+14155238886';

                String formattedToNumber = reqData.toNumber.startsWith('whatsapp:')
                    ? reqData.toNumber
                    : 'whatsapp:' + reqData.toNumber;

                String payload = 'From=' + EncodingUtil.urlEncode(fromNumber, 'UTF-8')
                    + '&To=' + EncodingUtil.urlEncode(formattedToNumber, 'UTF-8')
                    + '&Body=' + EncodingUtil.urlEncode(reqData.messageBody, 'UTF-8');

                req.setBody(payload);

                Http http = new Http();
                HttpResponse res = http.send(req);

                System.debug('Response: ' + res.getStatusCode() + ' - ' + res.getBody());

            } catch (Exception e) {
                System.debug('Error: ' + e.getMessage());
            }
        }
    }
}