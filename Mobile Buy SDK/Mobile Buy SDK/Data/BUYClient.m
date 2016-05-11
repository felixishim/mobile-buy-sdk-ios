//
//  BUYDataClient.m
//  Mobile Buy SDK
//
//  Created by Shopify.
//  Copyright (c) 2015 Shopify Inc. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "BUYClient_Internal.h"

#import "BUYAddress.h"
#import "BUYCart.h"
#import "BUYCheckout.h"
#import "BUYCreditCard.h"
#import "BUYCreditCardToken.h"
#import "BUYCollection.h"
#import "BUYError.h"
#import "BUYGiftCard.h"
#import "BUYModelManager.h"
#import "BUYOrder.h"
#import "BUYProduct.h"
#import "BUYPaymentSessionProvider.h"
#import "BUYShippingRate.h"
#import "BUYShop.h"
#import "BUYShopifyErrorCodes.h"
#import "NSDecimalNumber+BUYAdditions.h"
#import "NSDictionary+BUYAdditions.h"
#import "NSURLComponents+BUYAdditions.h"

#if __has_include(<PassKit/PassKit.h>)
@import PassKit;
#endif

#define kGET @"GET"
#define kPOST @"POST"
#define kPATCH @"PATCH"
#define kPUT @"PUT"
#define kDELETE @"DELETE"

#define kJSONType @"application/json"
#define kMinSuccessfulStatusCode 200
#define kMaxSuccessfulStatusCode 299

NSString * const BUYVersionString = @"1.3";

NSString *const kShopifyError = @"shopify";

static NSString *const kBUYClientPathProductPublications = @"product_listings";
static NSString *const kBUYClientPathCollectionPublications = @"collection_listings";

NSString *const BUYClientCustomerAccessToken = @"X-Shopify-Customer-Access-Token";

@interface BUYClient () <NSURLSessionDelegate>

@property (nonatomic, strong) NSString *shopDomain;
@property (nonatomic, strong) NSString *apiKey;
@property (nonatomic, strong) NSString *appId;

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSString *merchantId;

@end

@implementation BUYClient

- (instancetype)init { return nil; }

- (instancetype)initWithShopDomain:(NSString *)shopDomain apiKey:(NSString *)apiKey appId:(NSString *)appId
{
	if (shopDomain.length == 0) {
		NSException *exception = [NSException exceptionWithName:@"Bad shop domain" reason:@"Please ensure you initialize with a shop domain" userInfo:nil];
		@throw exception;
	}
	
	self = [super init];
	if (self) {
		self.modelManager = [BUYModelManager modelManager];
		self.shopDomain = shopDomain;
		self.apiKey = apiKey;
		self.appId = appId;
		self.applicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"] ?: @"";
		self.queue = dispatch_get_main_queue();
		self.session = [self urlSession];
		self.pageSize = 25;
	}
	return self;
}

- (NSURLSession *)urlSession
{
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
	
	NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
	
	config.HTTPAdditionalHeaders = @{@"User-Agent": [NSString stringWithFormat:@"Mobile Buy SDK iOS/%@/%@", BUYVersionString, bundleIdentifier]};
	
	return [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
}

#pragma mark - Storefront

- (void)setPageSize:(NSUInteger)pageSize
{
	_pageSize = MAX(MIN(pageSize, 250), 1);
}

- (BOOL)hasReachedEndOfPage:(NSArray *)lastFetchedObjects
{
	return [lastFetchedObjects count] < self.pageSize;
}

- (NSURLSessionDataTask *)getShop:(BUYDataShopBlock)block
{
	NSURLComponents *shopComponents = [self URLComponentsForShop];
	
	return [self getRequestForURL:shopComponents.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		BUYShop *shop = nil;
		if (json && !error) {
			shop = [self.modelManager insertShopWithJSONDictionary:json];
		}
		block(shop, error);
	}];
}

- (NSURLSessionDataTask *)getProductsPage:(NSUInteger)page completion:(BUYDataProductListBlock)block
{
	NSURLComponents *components = [self URLComponentsForChannelsAppendingPath:kBUYClientPathProductPublications
																   queryItems:@{@"limit" : [NSString stringWithFormat:@"%lu", (unsigned long)self.pageSize],
																				@"page" : [NSString stringWithFormat:@"%lu", (unsigned long)page]}];
	
	return [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		
		NSArray *products = nil;
		if (json && !error) {
			products = [self.modelManager insertProductsWithJSONArray:json[kBUYClientPathProductPublications]];
		}
		block(products, page, [self hasReachedEndOfPage:products] || error, error);
	}];
}

- (NSURLSessionDataTask *)getProductById:(NSString *)productId completion:(BUYDataProductBlock)block;
{
	return [self getProductsByIds:@[productId] completion:^(NSArray *products, NSError *error) {
		if (products.count > 0) {
			block(products[0], error);
		} else {
			if (!error) {
				error = [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidProductID userInfo:@{ NSLocalizedDescriptionKey : @"Product ID is not valid. Confirm the product ID on your shop's admin and also ensure that the visibility is on for the Mobile App channel." }];
			}
			block(nil, error);
		}
	}];
}

- (NSURLSessionDataTask *)getProductsByIds:(NSArray *)productIds completion:(BUYDataProductsBlock)block
{
	NSURLComponents *components = [self URLComponentsForChannelsAppendingPath:kBUYClientPathProductPublications
																   queryItems:@{@"product_ids" : [productIds componentsJoinedByString:@","]}];
	
	return [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		
		NSArray *products = nil;
		if (json && !error) {
			products = [self.modelManager insertProductsWithJSONArray:json[kBUYClientPathProductPublications]];
		}
		if (!error && products.count == 0) {
			error = [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidProductID userInfo:@{ NSLocalizedDescriptionKey : @"Product IDs are not valid. Confirm the product IDs on your shop's admin and also ensure that the visibility is on for the Mobile App channel." }];
		}
		block(products, error);
	}];
}

- (NSURLSessionDataTask *)getCollections:(BUYDataCollectionsBlock)block
{
	return [self getCollectionsPage:1 completion:^(NSArray<BUYCollection *> *collections, NSUInteger page, BOOL reachedEnd, NSError *error) {
		block(collections, error);
	}];
}

- (NSURLSessionDataTask *)getCollectionsPage:(NSUInteger)page completion:(BUYDataCollectionsListBlock)block
{
	NSURLComponents *components = [self URLComponentsForChannelsAppendingPath:kBUYClientPathCollectionPublications
																   queryItems:@{@"limit" : [NSString stringWithFormat:@"%lu", (unsigned long)self.pageSize],
																				@"page" : [NSString stringWithFormat:@"%lu", (unsigned long)page]}];
	return [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		
		NSArray *collections = nil;
		if (json && !error) {
			collections = [self.modelManager buy_objectsWithEntityName:[BUYCollection entityName] JSONArray:json[kBUYClientPathCollectionPublications]];
		}
		block(collections, page, [self hasReachedEndOfPage:collections], error);
	}];
}

- (NSURLSessionDataTask *)getProductsPage:(NSUInteger)page inCollection:(NSNumber *)collectionId completion:(BUYDataProductListBlock)block
{
	return [self getProductsPage:page inCollection:collectionId sortOrder:BUYCollectionSortCollectionDefault completion:block];
}

- (NSURLSessionDataTask *)getProductsPage:(NSUInteger)page inCollection:(NSNumber *)collectionId sortOrder:(BUYCollectionSort)sortOrder completion:(BUYDataProductListBlock)block
{
	NSURLSessionDataTask *task = nil;
	if (collectionId) {
		NSURLComponents *components = [self URLComponentsForChannelsAppendingPath:kBUYClientPathProductPublications
																	   queryItems:@{@"collection_id" : [NSString stringWithFormat:@"%lu", collectionId.longValue],
																					@"limit" : [NSString stringWithFormat:@"%lu", (unsigned long)self.pageSize],
																					@"page" : [NSString stringWithFormat:@"%lu", (unsigned long)page],
																					@"sort_by" : [BUYCollection sortOrderParameterForCollectionSort:sortOrder]}];
		
		task = [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
			
			NSArray *products = nil;
			if (json && !error) {
				products = [self.modelManager buy_objectsWithEntityName:[BUYProduct entityName] JSONArray:json[kBUYClientPathProductPublications]];
			}
			block(products, page, [self hasReachedEndOfPage:products] || error, error);
		}];
	}
	else {
		block(nil, 0, NO, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_NoCollectionIdSpecified userInfo:nil]);
	}
	
	return task;
}

#pragma mark - Helpers

- (NSError *)extractErrorFromResponse:(NSURLResponse *)response json:(NSDictionary *)json
{
	NSError *error = nil;
	NSInteger statusCode = [((NSHTTPURLResponse *) response) statusCode];
	if (statusCode < kMinSuccessfulStatusCode || statusCode > kMaxSuccessfulStatusCode) {
		error = [NSError errorWithDomain:NSURLErrorDomain code:statusCode userInfo:json];
	}
	return error;
}

#pragma mark - URL Components

- (NSURLComponents *)URLComponentsForChannelsAppendingPath:(NSString *)appendingPath queryItems:(NSDictionary*)queryItems
{
	return [self URLComponentsForAPIPath:[NSString stringWithFormat:@"apps/%@", self.appId] appendingPath:appendingPath queryItems:queryItems];
}

- (NSURLComponents *)URLComponentsForCheckoutsAppendingPath:(NSString *)appendingPath checkoutToken:(NSString *)checkoutToken queryItems:(NSDictionary*)queryItems
{
	NSString *apiPath = @"checkouts";
	if (checkoutToken) {
		apiPath = [NSString pathWithComponents:@[apiPath, checkoutToken]];
	}
	return [self URLComponentsForAPIPath:[apiPath copy] appendingPath:appendingPath queryItems:queryItems];
}

- (NSURLComponents *)URLComponentsForAPIPath:(NSString *)apiPath appendingPath:(NSString *)appendingPath queryItems:(NSDictionary*)queryItems
{
	NSMutableArray *pathComponents = [NSMutableArray array];
	[pathComponents addObject:@"/api"];
	[pathComponents addObject:apiPath];
	if (appendingPath) {
		[pathComponents addObject:appendingPath];
	}
	return [self URLComponentsForPathComponents:pathComponents queryItems:queryItems];
}

- (NSURLComponents *)URLComponentsForShop
{
	return [self URLComponentsForPathComponents:@[@"/meta"] queryItems:nil];
}

- (NSURLComponents *)URLComponentsForPathComponents:(NSArray*)pathComponents queryItems:(NSDictionary*)queryItems
{
	NSURLComponents *components = [[NSURLComponents alloc] init];
	components.scheme = @"https";
	components.host = self.shopDomain;
	components.path = [[NSString pathWithComponents:pathComponents] stringByAppendingPathExtension:@"json"];
	[components setQueryItemsWithDictionary:queryItems];
	return components;
}

#pragma mark - Checkout

- (void)handleCheckoutResponse:(NSDictionary *)json error:(NSError *)error block:(BUYDataCheckoutBlock)block
{
	BUYCheckout *checkout = nil;
	if (!error) {
		checkout = [self.modelManager insertCheckoutWithJSONDictionary:json[@"checkout"]];
	}
	block(checkout, error);
}

- (void)configureCheckout:(BUYCheckout *)checkout
{
	checkout.marketingAttribution = @{@"medium": @"iOS", @"source": self.applicationName};
	checkout.sourceName = @"mobile_app";
	if (self.urlScheme || checkout.webReturnToURL) {
		checkout.webReturnToURL = checkout.webReturnToURL ?: [NSURL URLWithString:self.urlScheme];
		checkout.webReturnToLabel = checkout.webReturnToLabel ?: [@"Return to " stringByAppendingString:self.applicationName];
	}
}

- (NSURLSessionDataTask *)createCheckout:(BUYCheckout *)checkout completion:(BUYDataCheckoutBlock)block
{
	// Inject channel and marketing attributions
	[self configureCheckout:checkout];
	
	NSDictionary *json = [checkout jsonDictionaryForCheckout];
	return [self postCheckout:json completion:block];
}

- (NSURLSessionDataTask *)createCheckoutWithCartToken:(NSString *)cartToken completion:(BUYDataCheckoutBlock)block
{
	BUYCheckout *checkout = [self.modelManager checkoutwithCartToken:cartToken];
	[self configureCheckout:checkout];
	
	NSDictionary *json = [checkout jsonDictionaryForCheckout];
	return [self postCheckout:json completion:block];
}

- (NSURLSessionDataTask *)postCheckout:(NSDictionary *)checkoutJSON completion:(BUYDataCheckoutBlock)block
{
	NSURLSessionDataTask *task = nil;
	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:checkoutJSON options:0 error:&error];
	
	if (data && !error) {
		NSURLComponents *components = [self URLComponentsForCheckoutsAppendingPath:nil checkoutToken:nil queryItems:nil];
		
		task = [self postRequestForURL:components.URL body:data completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
			[self handleCheckoutResponse:json error:error block:block];
		}];
	}
	
	return task;
}

- (NSURLSessionDataTask *)applyGiftCardWithCode:(NSString *)giftCardCode toCheckout:(BUYCheckout *)checkout completion:(BUYDataCheckoutBlock)block
{
	NSURLSessionDataTask *task = nil;
	if (giftCardCode.length == 0) {
		block(nil, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_NoGiftCardSpecified userInfo:nil]);
	}
	else {
		BUYGiftCard *giftCard = [self.modelManager giftCardWithCode:giftCardCode];
		NSURLComponents *components = [self URLComponentsForCheckoutsAppendingPath:@"gift_cards"
																	 checkoutToken:checkout.token
																		queryItems:nil];
		
		task = [self postRequestForURL:components.URL
								object:giftCard
					 completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
						 if (!error) {
							 [self updateCheckout:checkout withGiftCardDictionary:json[@"gift_card"] addingGiftCard:YES];
						 }
						 block(checkout, error);
					 }];
	}
	
	return task;
}

- (NSURLSessionDataTask *)removeGiftCard:(BUYGiftCard *)giftCard fromCheckout:(BUYCheckout *)checkout completion:(BUYDataCheckoutBlock)block
{
	NSURLSessionDataTask *task = nil;
	if (giftCard.identifier) {
		NSURLComponents *components = [self URLComponentsForCheckoutsAppendingPath:[NSString stringWithFormat:@"gift_cards/%@", giftCard.identifier]
																	 checkoutToken:checkout.token
																		queryItems:nil];
		task = [self deleteRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
			if (!error) {
				[self updateCheckout:checkout withGiftCardDictionary:json[@"gift_card"] addingGiftCard:NO];
			}
			block(checkout, error);
		}];
	}
	else {
		block(nil, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_NoGiftCardSpecified userInfo:nil]);
	}
	
	return task;
}

- (void)updateCheckout:(BUYCheckout *)checkout withGiftCardDictionary:(NSDictionary *)giftCardDictionary addingGiftCard:(BOOL)addingGiftCard
{
	if (addingGiftCard) {
		BUYGiftCard *giftCard = [self.modelManager insertGiftCardWithJSONDictionary:giftCardDictionary];
		[checkout.giftCardsSet addObject:giftCard];
	} else {
		[checkout removeGiftCardWithIdentifier:giftCardDictionary[@"id"]];
	}
	
	checkout.paymentDue = [NSDecimalNumber buy_decimalNumberFromJSON:giftCardDictionary[@"checkout"][@"payment_due"]];

	// Marking the checkout as clean. The properties we have updated above we don't need to re-sync with Shopify.
	// There's also an issue with gift cards where syncing the gift card JSON won't work since the update endpoint
	// doesn't accept the gift card without a gift card code (which we do not have).
	[checkout markAsClean];
}

- (NSURLSessionDataTask *)getCheckout:(BUYCheckout *)checkout completion:(BUYDataCheckoutBlock)block
{
	NSURLComponents *components = [self URLComponentsForCheckoutsAppendingPath:nil
																 checkoutToken:checkout.token
																	queryItems:nil];
	return [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		[self handleCheckoutResponse:json error:error block:block];
	}];
}

- (NSURLSessionDataTask *)updateCheckout:(BUYCheckout *)checkout completion:(BUYDataCheckoutBlock)block
{
	NSDictionary *json = [checkout jsonDictionaryForCheckout];
	NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
	
	NSURLSessionDataTask *task = nil;
	if ([checkout hasToken]) {
		NSURLComponents *components = [self URLComponentsForCheckoutsAppendingPath:nil
																	 checkoutToken:checkout.token
																		queryItems:nil];
		task = [self patchRequestForURL:components.URL body:data completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
			[self handleCheckoutResponse:json error:error block:block];
		}];
	}
	return task;
}

- (NSURLSessionDataTask*)completeCheckout:(BUYCheckout *)checkout paymentToken:(id<BUYPaymentToken>)paymentToken completion:(BUYDataCheckoutBlock)block
{
	NSAssert(checkout, @"Failed to complete checkout. Checkout must not be nil");
	
	NSURLSessionDataTask *task = nil;
	
	if ([checkout hasToken]) {
		
		BOOL isFree = (checkout.paymentDue && checkout.paymentDue.floatValue == 0);
		
		NSData *data = nil;
		if (paymentToken) {
			data = [NSJSONSerialization dataWithJSONObject:[paymentToken jsonRepresentation] options:0 error:nil];
		}
		
		if (data || isFree) {
			task = [self checkoutCompletionRequestWithCheckout:checkout body:data completion:block];
		}
		
	} else {
		block(nil, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidCheckoutObject userInfo:nil]);
	}
	
	return task;
}

- (NSURLSessionDataTask *)checkoutCompletionRequestWithCheckout:(BUYCheckout *)checkout body:(NSData *)body completion:(BUYDataCheckoutBlock)block
{
	NSURLComponents *components = [self URLComponentsForCheckoutsAppendingPath:@"complete"
																 checkoutToken:checkout.token
																	queryItems:nil];
	return [self postRequestForURL:components.URL body:body completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		[self handleCheckoutResponse:json error:error block:block];
	}];
}

- (NSURLSessionDataTask *)getCompletionStatusOfCheckout:(BUYCheckout *)checkout completion:(BUYDataCheckoutStatusBlock)block
{
	NSURLSessionDataTask *task = nil;
	if ([checkout hasToken]) {
		task = [self getCompletionStatusOfCheckoutToken:checkout.token completion:block];
	}
	else {
		block(BUYStatusUnknown, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidCheckoutObject userInfo:nil]);
	}
	return task;
}

- (NSURLSessionDataTask *)getCompletionStatusOfCheckoutURL:(NSURL *)url completion:(BUYDataCheckoutStatusBlock)block
{
	NSString *token = nil;
	
	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	for (NSURLQueryItem *item in components.queryItems) {
		
		if ([item.name isEqualToString:@"checkout[token]"]) {
			token = item.value;
		}
	}
	
	if (token) {
		return [self getCompletionStatusOfCheckoutToken:token completion:block];
	}
	else {
		block(BUYStatusUnknown, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidCheckoutObject userInfo:nil]);
		return nil;
	}
}

- (NSURLSessionDataTask *)getCompletionStatusOfCheckoutToken:(NSString *)token completion:(BUYDataCheckoutStatusBlock)block
{
	NSURLComponents *components = [self URLComponentsForCheckoutsAppendingPath:@"processing"
																 checkoutToken:token
																	queryItems:nil];
	return [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
		block([BUYClient statusForStatusCode:statusCode error:error], error);
	}];
}

#pragma mark - Shipping Rates

- (NSURLSessionDataTask *)getShippingRatesForCheckout:(BUYCheckout *)checkout completion:(BUYDataShippingRatesBlock)block
{
	NSURLSessionDataTask *task = nil;
	if ([checkout hasToken]) {
        NSURLComponents *components = [self URLComponentsForCheckoutsAppendingPath:@"shipping_rates" checkoutToken:checkout.token queryItems:@{ @"checkout" : @"" }];
		task = [self getRequestForURL:components.URL completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
			NSArray *shippingRates = nil;
			if (json && !error) {
				shippingRates = [self.modelManager insertShippingRatesWithJSONArray:json[@"shipping_rates"]];
			}
			
			NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
			block(shippingRates, [BUYClient statusForStatusCode:statusCode error:error], error);
		}];
	}
	else {
		block(nil, BUYStatusUnknown, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidCheckoutObject userInfo:nil]);
	}
	return task;
}

#pragma mark - Payments

- (NSURLSessionDataTask *)storeCreditCard:(BUYCreditCard *)creditCard checkout:(BUYCheckout *)checkout completion:(BUYDataCreditCardBlock)completion
{
	NSAssert(checkout, @"Failed to store credit card. No checkout provided.");
	NSAssert(checkout.token, @"Failed to store credit card. No checkout token provided.");
	NSAssert(creditCard, @"Failed to store credit card. No credit card provided.");
	
	NSMutableDictionary *json = [[NSMutableDictionary alloc] init];
	json[@"token"]            = checkout.token;
	json[@"credit_card"]      = [creditCard jsonDictionaryForCheckout];
	if (checkout.billingAddress) {
		json[@"billing_address"] = [checkout.billingAddress jsonDictionaryForCheckout];
	}
	
	NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"checkout" : json } options:0 error:nil];
	if (data) {
		return [self postPaymentRequestWithCheckout:checkout body:data completion:^(BUYCheckout *checkout, NSString *paymentSessionId, NSError *error) {
			id<BUYPaymentToken> provider = [[BUYCreditCardToken alloc] initWithPaymentSessionID:paymentSessionId];
			completion(checkout, provider, error);
		}];
		
	} else {
		completion(nil, nil, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidCheckoutObject userInfo:nil]);
		return nil;
	}
}

- (NSURLSessionDataTask *)removeProductReservationsFromCheckout:(BUYCheckout *)checkout completion:(BUYDataCheckoutBlock)block
{
	NSURLSessionDataTask *task = nil;
	if ([checkout hasToken]) {
		checkout.reservationTime = @0;
		task = [self updateCheckout:checkout completion:block];
	} else {
		block(checkout, [NSError errorWithDomain:kShopifyError code:BUYShopifyError_InvalidCheckoutObject userInfo:nil]);
	}
	return task;
}

#pragma mark - Helpers

+ (BUYStatus)statusForStatusCode:(NSUInteger)statusCode error:(NSError *)error
{
	BUYStatus status = BUYStatusUnknown;
	if (statusCode == BUYStatusPreconditionFailed) {
		status = BUYStatusPreconditionFailed;
	}
	else if (statusCode == BUYStatusNotFound) {
		status = BUYStatusNotFound;
	}
	else if (error || statusCode == BUYStatusFailed) {
		status = BUYStatusFailed;
	}
	else if (statusCode == BUYStatusProcessing) {
		status = BUYStatusProcessing;
	}
	else if (statusCode == BUYStatusComplete) {
		status = BUYStatusComplete;
	}
	return status;
}

- (NSError *)errorFromJSON:(NSDictionary *)errorDictionary statusCode:(NSInteger)statusCode
{
	return [[NSError alloc] initWithDomain:kShopifyError code:statusCode userInfo:errorDictionary];
}

- (NSURLSessionDataTask *)requestForURL:(NSURL *)url method:(NSString *)method object:(id <BUYSerializable>)object completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	NSDictionary *json = [object jsonDictionaryForCheckout];
	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
	NSURLSessionDataTask *task = nil;
	if (data && !error) {
		task = [self requestForURL:url method:method body:data completionHandler:completionHandler];
	}
	return task;
}

- (void)startTask:(NSURLSessionDataTask *)task
{
	[task resume];
}

- (NSURLSessionDataTask *)requestForURL:(NSURL *)url method:(NSString *)method body:(NSData *)body completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
	request.HTTPBody = body;
	
	[request addValue:[self authorizationHeader] forHTTPHeaderField:@"Authorization"];
	[request addValue:kJSONType forHTTPHeaderField:@"Content-Type"];
	[request addValue:kJSONType forHTTPHeaderField:@"Accept"];
	
	if (self.customerToken) {
		[request addValue:self.customerToken forHTTPHeaderField:BUYClientCustomerAccessToken];
	}
	
	request.HTTPMethod = method;
	NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
		NSDictionary *json = nil;
		BOOL unauthorized = statusCode == 401;
		BOOL failedValidation = statusCode == 422;
		
		if (unauthorized) {
			error = [[NSError alloc] initWithDomain:kShopifyError code:statusCode userInfo:nil];
		}
		else {
			//2 is the minimum amount of data {} for a JSON Object. Just ignore anything less.
			if ((!error || failedValidation) && [data length] > 2) {
				id jsonData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
				json = [jsonData isKindOfClass:[NSDictionary class]] ? jsonData : nil;
			}
			
			if (statusCode < kMinSuccessfulStatusCode || statusCode > kMaxSuccessfulStatusCode) {
				error = [self errorFromJSON:json statusCode:statusCode];
			}
		}
		dispatch_async(self.queue, ^{
			completionHandler(json, response, error);
		});
	}];
	[self startTask:task];
	return task;
}

- (NSURLSessionDataTask *)postPaymentRequestWithCheckout:(BUYCheckout *)checkout body:(NSData *)body completion:(void (^)(BUYCheckout *checkout, NSString *paymentSessionId, NSError *error))block
{
	return [self requestForURL:checkout.paymentURL method:kPOST body:body completionHandler:^(NSDictionary *json, NSURLResponse *response, NSError *error) {
		NSString *paymentSessionId = nil;
		if (!error) {
			paymentSessionId = json[@"id"];
			checkout.paymentSessionId = paymentSessionId;
		}
		block(checkout, paymentSessionId, error);
	}];
}

- (NSURLSessionDataTask *)getRequestForURL:(NSURL *)url completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	return [self requestForURL:url method:kGET body:nil completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)postRequestForURL:(NSURL *)url object:(id <BUYSerializable>)object completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	return [self requestForURL:url method:kPOST object:object completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)putRequestForURL:(NSURL *)url body:(NSData *)body completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	return [self requestForURL:url method:kPUT body:body completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)postRequestForURL:(NSURL *)url body:(NSData *)body completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	return [self requestForURL:url method:kPOST body:body completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)patchRequestForURL:(NSURL *)url object:(id <BUYSerializable>)object completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	return [self requestForURL:url method:kPATCH object:object completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)patchRequestForURL:(NSURL *)url body:(NSData *)body completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	return [self requestForURL:url method:kPATCH body:body completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)deleteRequestForURL:(NSURL *)url completionHandler:(void (^)(NSDictionary *json, NSURLResponse *response, NSError *error))completionHandler
{
	return [self requestForURL:url method:kDELETE body:nil completionHandler:completionHandler];
}

- (NSString *)authorizationHeader
{
	NSData *data = [_apiKey dataUsingEncoding:NSUTF8StringEncoding];
	return [NSString stringWithFormat:@"%@ %@", @"Basic", [data base64EncodedStringWithOptions:0]];
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
	NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
	
	if (protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust) {
		
		SecTrustResultType resultType;
		SecTrustEvaluate(protectionSpace.serverTrust, &resultType);
		
		BOOL trusted = (resultType == kSecTrustResultUnspecified) || (resultType == kSecTrustResultProceed);
		
		if (trusted) {
			NSURLCredential *credential = [NSURLCredential credentialForTrust:protectionSpace.serverTrust];
			completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
		}
		else {
			completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, NULL);
		}
		
	}
	else {
		completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
	}
}

#pragma mark - Deprecations

- (void)enableApplePayWithMerchantId:(NSString *)merchantId
{
	self.merchantId = merchantId;
}

@end
