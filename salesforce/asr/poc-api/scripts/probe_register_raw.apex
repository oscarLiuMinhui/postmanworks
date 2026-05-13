AscottPayloadBuilder.RegisterRequest req = new AscottPayloadBuilder.RegisterRequest();
req.registrationType   = 'FULL';
req.salutation         = 'Mr';
req.firstName          = 'Test';
req.lastName           = 'ProbeUser';
Long ts = DateTime.now().getTime();
req.email              = 'test.probe.' + String.valueOf(ts) + '@mailinator.com';
req.password           = 'Test1234!';
req.mobileNumber       = '+65|9' + String.valueOf(ts).right(7);
req.countryOfResidence = 'SG';
req.offers             = new List<String>{ 'M' };

Map<String, Object> payload = AscottPayloadBuilder.register(null, req);
AscottCrypto.EncryptResult enc = AscottCrypto.encryptPayload(payload);

HttpRequest httpReq = new HttpRequest();
httpReq.setEndpoint('callout:Ascott_API/?xs_app=' + EncodingUtil.urlEncode(enc.xsApp, 'UTF-8') + '&t=' + enc.encryptedT);
httpReq.setMethod('GET');
httpReq.setHeader('Accept', 'application/json');
httpReq.setTimeout(10000);

HttpResponse res = new Http().send(httpReq);
System.debug('HTTP status : ' + res.getStatusCode());
System.debug('Raw body   : ' + res.getBody());
