/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */
#import <Foundation/Foundation.h>

#include <libxml/parser.h>

typedef enum {
    FSXMLHttpRequestError_NoError = 0,
    FSXMLHttpRequestError_Connection_Failed,
    FSXMLHttpRequestError_Invalid_Http_Status,
    FSXMLHttpRequestError_XML_Parser_Failed
} FSXMLHttpRequestError;

@interface FSXMLHttpRequest : NSObject<NSURLConnectionDelegate> {
    NSString *_url;
    NSURLConnection *_connection;
    NSInteger _httpStatus;
    NSMutableData *_receivedData;
    xmlDocPtr _xmlDocument;
    FSXMLHttpRequestError lastError;
}

@property (nonatomic,copy) NSString *url;
@property (copy) void (^onCompletion)();
@property (copy) void (^onFailure)();
@property (readonly) FSXMLHttpRequestError lastError;

- (void)start;
- (void)cancel;

- (NSArray *)performXPathQuery:(NSString *)query;
- (NSString *)contentForNode:(xmlNodePtr)node;
- (NSString *)contentForNodeAttribute:(xmlNodePtr)node attribute:(const char *)attr;

@end