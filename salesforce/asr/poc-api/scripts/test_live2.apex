// Debug version — shows raw HTTP response before parsing
AscottCrypto.EncryptResult enc = AscottCrypto.encryptPayload(
    AscottPayloadBuilder.checkUserExist(null, 'zaldyantonio@gmail.com', null)
);

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Ascott_API/?xs_app=' + EncodingUtil.urlEncode(enc.xsApp, 'UTF-8') + '&t=' + enc.encryptedT);
req.setMethod('GET');
req.setHeader('Accept', 'application/json');
req.setTimeout(10000);

HttpResponse res = new Http().send(req);
System.debug('Status code : ' + res.getStatusCode());
System.debug('Body        : ' + res.getBody());
