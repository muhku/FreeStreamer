/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSXMLHttpRequest.h"

#import <libxml/xpath.h>

@interface FSXMLHttpRequest (PrivateMethods)
- (const char *)detectEncoding;
- (void)parseResponseData;
- (void)parseXMLNode:(xmlNodePtr)node xPathQuery:(NSString *)xPathQuery;

@end

@implementation FSXMLHttpRequest

@synthesize url=_url;
@synthesize onCompletion;
@synthesize onFailure;
@synthesize lastError=_lastError;

- (id)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (void)start
{
    if (_connection) {
        return;
    }
    
    _lastError = FSXMLHttpRequestError_NoError;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:self.url]
                                             cachePolicy:NSURLRequestUseProtocolCachePolicy
                                         timeoutInterval:60.0];
    
    @synchronized (self) {
        _receivedData = [NSMutableData data];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    }
    
    if (!_connection) {
        onFailure();
        return;
    }
}

- (void)cancel
{
    if (!_connection) {
        return;
    }
    @synchronized (self) {
        [_connection cancel];
        _connection = nil;
    }
}

/*
 * =======================================
 * NSURLConnectionDelegate
 * =======================================
 */

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    _httpStatus = [httpResponse statusCode];
    
    [_receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [_receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    @synchronized (self) {
        assert(_connection == connection);
        _connection = nil;
        _receivedData = nil;
    }
    
    _lastError = FSXMLHttpRequestError_Connection_Failed;
    onFailure();
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    assert(_connection == connection);
    
    @synchronized (self) {
        _connection = nil;
    }
    
    if (_httpStatus != 200) {
        _lastError = FSXMLHttpRequestError_Invalid_Http_Status;
        onFailure();
        return;
    }
    
    const char *encoding = [self detectEncoding];
    
    _xmlDocument = xmlReadMemory([_receivedData bytes],
                                 [_receivedData length],
                                 "",
                                 encoding,
                                 0);
    
    if (!_xmlDocument) {
        _lastError = FSXMLHttpRequestError_XML_Parser_Failed;
        onFailure();
        return;
    }
    
    [self parseResponseData];
    
    xmlFreeDoc(_xmlDocument), _xmlDocument = nil;
    
    onCompletion();
}

/*
 * =======================================
 * XML handling
 * =======================================
 */

- (NSArray *)performXPathQuery:(NSString *)query
{
    NSMutableArray *resultNodes = [NSMutableArray array];
    xmlXPathContextPtr xpathCtx = NULL; 
    xmlXPathObjectPtr xpathObj = NULL;
    
    xpathCtx = xmlXPathNewContext(_xmlDocument);
    if (xpathCtx == NULL) {
		goto cleanup;
    }
    
    xpathObj = xmlXPathEvalExpression((xmlChar *)[query cStringUsingEncoding:NSUTF8StringEncoding], xpathCtx);
    if (xpathObj == NULL) {
		goto cleanup;
    }
	
	xmlNodeSetPtr nodes = xpathObj->nodesetval;
	if (!nodes) {
		goto cleanup;
	}
	
	for (size_t i = 0; i < nodes->nodeNr; i++) {
        [self parseXMLNode:nodes->nodeTab[i] xPathQuery:query];
	}
    
cleanup:
    if (xpathObj) {
        xmlXPathFreeObject(xpathObj);
    }
    if (xpathCtx) {
        xmlXPathFreeContext(xpathCtx);
    }
    return resultNodes;
}

- (NSString *)contentForNode:(xmlNodePtr)node
{
    NSString *stringWithContent;
    if (!node) {
        stringWithContent = [[NSString alloc] init];
    } else {
        xmlChar *content = xmlNodeGetContent(node);
        if (!content) {
            return stringWithContent;
        }
        stringWithContent = [NSString stringWithCString:(const char *)content encoding:NSUTF8StringEncoding];
        xmlFree(content);
    }
    return stringWithContent;
}

- (NSString *)contentForNodeAttribute:(xmlNodePtr)node attribute:(const char *)attr
{
    NSString *stringWithContent;
    if (!node) {
        stringWithContent = [[NSString alloc] init];
    } else {
        xmlChar *content = xmlGetProp(node, (const xmlChar *)attr);
        if (!content) {
            return stringWithContent;
        }
        stringWithContent = [NSString stringWithCString:(const char *)content encoding:NSUTF8StringEncoding];
        xmlFree(content);
    }
    return stringWithContent;
}

/*
 * =======================================
 * Helpers
 * =======================================
 */

- (const char *)detectEncoding
{
    const char *encoding = 0;
    const char *header = strndup([_receivedData bytes], 60);
    
    if (strstr(header, "utf-8") || strstr(header, "UTF-8")) {
        encoding = "UTF-8";
    } else if (strstr(header, "iso-8859-1") || strstr(header, "ISO-8859-1")) {
        encoding = "ISO-8859-1";
    }
    
    free((void *)header);
    return encoding;
}

@end