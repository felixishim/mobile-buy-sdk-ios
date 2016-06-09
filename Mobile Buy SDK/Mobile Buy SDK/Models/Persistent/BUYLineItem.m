//
//  _BUYLineItem.m
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

#import "BUYLineItem.h"
#import "BUYCartLineItem.h"
#import "BUYProductVariant.h"

@implementation BUYLineItem

- (void)updateWithVariant:(BUYProductVariant *)variant
{
	self.variantId = variant.identifier;
	self.quantity = variant ? [NSDecimalNumber one] : [NSDecimalNumber zero];
	self.price = variant.price ?: [NSDecimalNumber zero];
	self.title = variant.title ?: @"";
	self.requiresShipping = variant.requiresShipping;
	self.compareAtPrice = variant.compareAtPrice;
	self.grams = variant.grams;
}

- (void)updateWithLineItem:(BUYCartLineItem *)lineItem
{
	[self updateWithVariant:lineItem.variant];
	self.quantity = lineItem.quantity;
}

+ (NSPredicate *)fetchPredicateWithJSON:(NSDictionary *)JSONDictionary
{
	NSNumber *variantId = JSONDictionary[@"variant_id"];
	return (variantId) ? [NSPredicate predicateWithFormat:@"%K = %@", BUYLineItemAttributes.variantId, variantId] : nil;
}

@end

@implementation BUYModelManager (BUYLineItemCreation)

- (BUYLineItem *)lineItemWithVariant:(BUYProductVariant *)variant
{
	BUYLineItem *lineItem = [self insertLineItemWithJSONDictionary:nil];
	[lineItem updateWithVariant:variant];
	return lineItem;
}

- (BUYLineItem *)lineItemWithCartLineItem:(BUYCartLineItem *)cartLineItem
{
	BUYLineItem *lineItem = [self insertLineItemWithJSONDictionary:nil];
	[lineItem updateWithLineItem:cartLineItem];
	return lineItem;
}

@end
