//
//  FlycutOperator.m
//  Flycut
//
//  Flycut by Gennadiy Potapov and contributors. Based on Jumpcut by Steve Cook.
//  Copyright 2011 General Arcade. All rights reserved.
//
//  This code is open-source software subject to the MIT License; see the homepage
//  at <https://github.com/TermiT/Flycut> for details.
//

// FlycutOperator owns and interacts with the FlycutStores, providing
// manipulation of the stores.

#import <Foundation/Foundation.h>
#import "FlycutOperator.h"
#import "MJCloudKitUserDefaultsSync.h"

@implementation FlycutOperator

- (id)init
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInt:40],
		@"rememberNum",
        [NSNumber numberWithInt:40],
        @"favoritesRememberNum",
		[NSNumber numberWithInt:1],
		@"savePreference",
        [NSDictionary dictionary],
        @"store",
        [NSNumber numberWithBool:YES],
        @"skipPasswordFields",
		[NSNumber numberWithBool:YES],
		@"skipPboardTypes",
		@"PasswordPboardType",
		@"skipPboardTypesList",
		[NSNumber numberWithBool:NO],
		@"skipPasswordLengths",
		@"12, 20, 32",
		@"skipPasswordLengthsList",
		[NSNumber numberWithBool:NO],
		@"revealPasteboardTypes",
        [NSNumber numberWithBool:YES], // do not commit with YES.  Use NO
        @"removeDuplicates",
        [NSNumber numberWithBool:YES], // do not commit with YES.  Use NO
        @"pasteMovesToTop",
        [NSNumber numberWithBool:NO],
        @"syncSettingsViaICloud",
        [NSNumber numberWithBool:NO],
        @"syncClippingsViaICloud",
        nil]];

	settingsSyncList = @[@"rememberNum",
						 @"favoritesRememberNum",
						 @"savePreference",
						 @"skipPasswordFields",
						 @"skipPboardTypes",
						 @"skipPboardTypesList",
						 @"skipPasswordLengths",
						 @"skipPasswordLengthsList",
						 @"removeDuplicates",
						 @"pasteMovesToTop"];
	[settingsSyncList retain];

	return self;
}

- (void)awakeFromNibDisplaying:(int) dispNum withDisplayLength:(int) dispLength withSaveSelector:(SEL) selector forTarget:(NSObject*) target
{
	displayNum = dispNum;
	displayLength = dispLength;
	saveSelector = selector;
	saveTarget = target;

	// Initialize the FlycutStore
	[self initializeStoresAndLoadContents];

	// Stack position starts @ 0 by default
	stackPosition = favoritesStackPosition = stashedStackPosition = 0;

	[self registerOrDeregisterICloudSync];
}

-(FlycutStore*) allocInitFlycutStoreRemembering:(int) remembering
{
	return [[FlycutStore alloc] initRemembering:remembering
									 displaying:displayNum
							  withDisplayLength:displayLength];
}

-(void) initializeStores
{
	// Fixme - These stores are not released anywhere.
	if ( !clippingStore )
	{
		clippingStore = [self allocInitFlycutStoreRemembering:[[NSUserDefaults standardUserDefaults] integerForKey:@"rememberNum"]];
		clippingStore.deleteDelegate = self;
	}
	else
	{
		[clippingStore setDisplayNum:displayNum];
		[clippingStore setDisplayLen:displayLength];
	}

	if ( ! favoritesStore )
	{
		favoritesStore = [self allocInitFlycutStoreRemembering:[[NSUserDefaults standardUserDefaults] integerForKey:@"favoritesRememberNum"]];
		favoritesStore.deleteDelegate = self;
	}
	else
	{
		[favoritesStore setDisplayNum:displayNum];
		[favoritesStore setDisplayLen:displayLength];
	}

	stashedStore = NULL;
}

-(void) initializeStoresAndLoadContents
{
	[self initializeStores];

	// If our preferences indicate that we are saving, load the dictionary from the saved plist
	// and use it to get everything set up.
	if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 1 ) {
		[self loadEngineFromPList];
	}
}

-(void) willShowPreferences
{
	issuedRememberResizeWarning = NO;
}

-(int) setRememberNum:(int)newRemember forPrimaryStore:(BOOL) isPrimaryStore
{
	int oldRemeber = [self rememberNum];

	// Ensure that we don't remember zero or fewer clippings.
	if ( newRemember <= 0 )
	{
		newRemember = oldRemeber;
		if ( newRemember <= 0 )
			newRemember = 40;
	}

	if ( newRemember < [self jcListCount] &&
		! issuedRememberResizeWarning &&
		! [[NSUserDefaults standardUserDefaults] boolForKey:@"stifleRememberResizeWarning"]
		) {

		NSString *choice = [self delegateAlertWithMessageText:@"Resize Stack"
											  informationText:@"Resizing the stack to a value below its present size will cause clippings to be lost."
												 buttonsTexts:@[@"Resize", @"Cancel", @"Don't Warn Me Again"]];
		if ( [choice isEqualToString:@"Cancel"] ) {
			// Cancel - Change to prior setting.
			newRemember = oldRemeber;
			if ( isPrimaryStore ) {
				[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:newRemember]
														 forKey:@"rememberNum"];
			} else {
				[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:newRemember]
														 forKey:@"favoritesRememberNum"];
			}
		} else if ( [choice isEqualToString:@"Don't Warn Me Again"] ) {
			// Don't Warn Me Again
			[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:YES]
													 forKey:@"stifleRememberResizeWarning"];
		} else {
			// Resize
			issuedRememberResizeWarning = YES;
		}
	}

	// Set the value.
	[clippingStore setRememberNum:newRemember];

	return newRemember;
}

-(void)toggleToFromFavoritesStore
{
    if (NULL != stashedStore)
        [self restoreStashedStore];
    else
        [self switchToFavoritesStore];
}

-(bool)favoritesStoreIsSelected
{
    return clippingStore == favoritesStore;
}

-(void)switchToFavoritesStore
{
    stashedStore = clippingStore;
    clippingStore = favoritesStore;
    stashedStackPosition = stackPosition;
    stackPosition = favoritesStackPosition;
}

- (bool)restoreStashedStore
{
    if (NULL != stashedStore)
    {
        clippingStore = stashedStore;
        stashedStore = NULL;
        favoritesStackPosition = stackPosition;
        stackPosition = stashedStackPosition;
        return YES;
    }
    return NO;
}

- (NSString*)getPasteFromStackPosition
{
	if ( [clippingStore jcListCount] > stackPosition ) {
		return [self getPasteFromIndex: stackPosition];
	}
	return nil;
}

- (bool)saveFromStack
{
    return [self saveFromStackWithPrefix:@""];
}

- (bool)saveFromStackWithPrefix:(NSString*) prefix
{
	return [self saveFromStore:clippingStore atIndex:stackPosition withPrefix:prefix];
}

- (bool)saveFromStore:(FlycutStore*)store atIndex:(int)index withPrefix:(NSString*) prefix
{
    if ( [store jcListCount] > index ) {
        // Get text from clipping store.
        NSString *pbFullText = [self clippingStringWithCount:index inStore:store];
        pbFullText = [pbFullText stringByReplacingOccurrencesOfString:@"\r" withString:@"\r\n"];

        // Get the Desktop directory:
        NSArray *paths = NSSearchPathForDirectoriesInDomains
        (NSDesktopDirectory, NSUserDomainMask, YES);
        NSString *desktopDirectory = [paths objectAtIndex:0];

        // Get the timestamp string:
        NSDate *currentDate = [NSDate date];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"YYYY-MM-dd 'at' HH.mm.ss"];
        NSString *dateString = [dateFormatter stringFromDate:currentDate];

        // Make a file name to write the data to using the Desktop directory:
        NSString *fileName = [NSString stringWithFormat:@"%@/%@%@Clipping %@.txt",
                              desktopDirectory, prefix, store == favoritesStore ? @"Favorite " : @"", dateString];

        // Save content to the file
        [pbFullText writeToFile:fileName
                  atomically:NO
                    encoding:NSNonLossyASCIIStringEncoding
                       error:nil];
        return YES;
    }
    return NO;
}

- (bool)saveFromStackToFavorites
{
    if ( clippingStore != favoritesStore && [clippingStore jcListCount] > stackPosition ) {
        // Get text from clipping store.
        [favoritesStore addClipping:[clippingStore clippingAtPosition:stackPosition] ];
        [self clearItemAtStackPosition];
        return YES;
    }
    return NO;
}

- (NSString*)getPasteFromIndex:(int) position {
	NSString *clipping = [self getClipFromCount:position];

	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"pasteMovesToTop"] ) {
		[clippingStore clippingMoveToTop:position];
		stackPosition = 0;

		[self actionAfterListModification];
	}
	return clipping;
}

-(NSString*)getClipFromCount:(int)indexInt
{
    NSString *pbFullText;
    NSArray *pbTypes;
    if ( (indexInt + 1) > [clippingStore jcListCount] ) {
        // We're asking for a clipping that isn't there yet
		// This only tends to happen immediately on startup when not saving, as the entire list is empty.
        DLog(@"Out of bounds request to jcList ignored.");
        return nil;
    }
    return [self clippingStringWithCount:indexInt];
}

-(BOOL)shouldSkip:(NSString *)contents ofType:(NSString *)type
{
	// Check to see if we are skipping passwords based on length and characters.
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"skipPasswordFields"] )
	{
		// Check to see if they want a little help figuring out what types to enter.
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"revealPasteboardTypes"] )
			[clippingStore addClipping:type ofType:type fromAppLocalizedName:@"Flycut" fromAppBundleURL:nil atTimestamp:0];
		[self actionAfterListModification];

		__block bool skipClipping = NO;

		// Check the array of types to skip.
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"skipPboardTypes"] )
		{
			NSArray *typesArray = [[[[NSUserDefaults standardUserDefaults] stringForKey:@"skipPboardTypesList"] stringByReplacingOccurrencesOfString:@" " withString:@""] componentsSeparatedByString: @","];
			[typesArray enumerateObjectsUsingBlock:^(id typeString, NSUInteger idx, BOOL *stop)
			{
				if ( [type isEqualToString:typeString] )
				{
					skipClipping = YES;
					*stop = YES;
				}
			}];
		}
		if (skipClipping)
			return YES;

		// Check the array of lengths to skip for suspicious strings.
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"skipPasswordLengths"] )
		{
			int contentsLength = [contents length];
			NSArray *lengthsArray = [[[[NSUserDefaults standardUserDefaults] stringForKey:@"skipPasswordLengthsList"] stringByReplacingOccurrencesOfString:@" " withString:@""] componentsSeparatedByString: @","];
			[lengthsArray enumerateObjectsUsingBlock:^(id lengthString, NSUInteger idx, BOOL *stop)
			{
				if ( [lengthString integerValue] == contentsLength )
				{
					NSRange uppercaseLetter = [contents rangeOfCharacterFromSet: [NSCharacterSet uppercaseLetterCharacterSet]];
					NSRange lowercaseLetter = [contents rangeOfCharacterFromSet: [NSCharacterSet lowercaseLetterCharacterSet]];
					NSRange decimalDigit = [contents rangeOfCharacterFromSet: [NSCharacterSet decimalDigitCharacterSet]];
					NSRange punctuation = [contents rangeOfCharacterFromSet: [NSCharacterSet punctuationCharacterSet]];
					NSRange symbol = [contents rangeOfCharacterFromSet: [NSCharacterSet symbolCharacterSet]];
					NSRange control = [contents rangeOfCharacterFromSet: [NSCharacterSet controlCharacterSet]];
					NSRange illegal = [contents rangeOfCharacterFromSet: [NSCharacterSet illegalCharacterSet]];
					NSRange whitespaceAndNewline = [contents rangeOfCharacterFromSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if ( NSNotFound == control.location
						&& NSNotFound == illegal.location
						&& NSNotFound == whitespaceAndNewline.location
						&& NSNotFound != uppercaseLetter.location
						&& NSNotFound != lowercaseLetter.location
						&& NSNotFound != decimalDigit.location
						&& ( NSNotFound != punctuation.location
							|| NSNotFound != symbol.location ) )
					{
						skipClipping = YES;
						*stop = YES;
					}
				}
			}];

			if (skipClipping)
				return YES;
		}
	}
	return NO;
}

-(void)setDisableStoreTo:(bool) value
{
    disableStore = value;
}

-(bool)storeDisabled
{
	return disableStore;
}

-(void)setClippingsStoreDelegate:(id<FlycutStoreDelegate>) delegate
{
	if ( !clippingStore )
		[self initializeStores];
	clippingStore.delegate = delegate;
}

-(void)setFavoritesStoreDelegate:(id<FlycutStoreDelegate>) delegate
{
	if ( !favoritesStore )
		[self initializeStores];
	favoritesStore.delegate = delegate;
}

-(int)indexOfClipping:(NSString*)contents ofType:(NSString*)type fromApp:(NSString *)appName withAppBundleURL:(NSString *)bundleURL
{
	return [clippingStore indexOfClipping:contents
								   ofType:type
					 fromAppLocalizedName:appName
						 fromAppBundleURL:bundleURL
							  atTimestamp:[[NSDate date] timeIntervalSince1970]];
}

-(bool)addClipping:(NSString*)contents ofType:(NSString*)type fromApp:(NSString *)appName withAppBundleURL:(NSString *)bundleURL target:(id)selectorTarget clippingAddedSelector:(SEL)clippingAddedSelector
{
	if ( [clippingStore jcListCount] == 0 || ! [contents isEqualToString:[clippingStore clippingContentsAtPosition:0]]) {
		bool success = [clippingStore addClipping:contents
										   ofType:type
							 fromAppLocalizedName:appName
								 fromAppBundleURL:bundleURL
									  atTimestamp:[[NSDate date] timeIntervalSince1970]];

//		The below tracks our position down down down... Maybe as an option?
//		if ( [clippingStore jcListCount] > 1 ) stackPosition++;
		stackPosition = 0;
        [selectorTarget performSelector:clippingAddedSelector];
		[self actionAfterListModification];

		return success;
    }
	return  NO;
}

- (void)willDeleteClippingFromStore:(id)store AtIndex:(int)index {
	if ( (!inhibitAutosaveClippings) // Avoid saving things that the user explicitly deletes.
		&& ( store == favoritesStore
		? [[[NSUserDefaults standardUserDefaults] valueForKey:@"saveForgottenFavorites"] boolValue]
		: [[[NSUserDefaults standardUserDefaults] valueForKey:@"saveForgottenClippings"] boolValue] ) )
	{
		// clipping is being removed, so save it before it gets lost.
		// Set to last item, save, and restore position.
		[self saveFromStore:store atIndex:index withPrefix:@"Autosave "];
	}
}

-(void)actionAfterListModification
{
	if ( !inhibitSaveEngineAfterListModification
		&& [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 2 )
		[self saveEngine];
}

-(int)jcListCount
{
	return [clippingStore jcListCount];
}

-(int)rememberNum
{
	return [clippingStore rememberNum];
}

-(int)stackPosition
{
	return stackPosition;
}

-(bool)setStackPositionToFirstItem
{
	if ( [clippingStore jcListCount] > 0 ) {
		stackPosition = 0;
		return YES;
	}
	return NO;
}

-(bool)setStackPositionToLastItem
{
	if ( [clippingStore jcListCount] > 0 ) {
		stackPosition = [clippingStore jcListCount] - 1;
		return YES;
	}
	return NO;
}

-(bool)setStackPositionToTenMoreRecent
{
	if ( [clippingStore jcListCount] > 0 ) {
		stackPosition = stackPosition - 10; if ( stackPosition < 0 ) stackPosition = 0;
		return YES;
	}
	return NO;
}

-(bool)setStackPositionToTenLessRecent
{
	if ( [clippingStore jcListCount] > 0 ) {
		stackPosition = stackPosition + 10; if ( stackPosition >= [clippingStore jcListCount] ) stackPosition = [clippingStore jcListCount] - 1;
		return YES;
	}
	return NO;
}

-(bool)clearItemAtStackPosition
{
    if ([clippingStore jcListCount] == 0)
        return NO;

	inhibitAutosaveClippings = YES; // Avoid saving things that the user explicitly deletes.
	[clippingStore clearItem:stackPosition];
	inhibitAutosaveClippings = NO;
	[self actionAfterListModification];

    return YES;
}

-(bool)setStackPositionTo:(int) newStackPosition
{
	if ( [clippingStore jcListCount] >= newStackPosition ) {
		stackPosition = newStackPosition;
		return YES;
	}
	return NO;
}

// Would probably be good to just prevent this scenario where it originates and
// delete this check.
-(void)adjustStackPositionIfOutOfBounds
{
	if (stackPosition >= [clippingStore jcListCount] && stackPosition != 0) { // deleted last item
		stackPosition = [clippingStore jcListCount] - 1;
	}
}

-(bool)stackPositionIsInBounds
{
	return ( [clippingStore jcListCount] > 0 && [clippingStore jcListCount] > stackPosition );
}

-(void)clearList
{
    [clippingStore clearList];
    [self actionAfterListModification];
}

-(void)mergeList
{
	[clippingStore mergeList];
}

-(BOOL) isValidClippingNumber:(NSNumber *)number {
	return [self isValidClippingNumber:number inStore:clippingStore];
}

-(BOOL) isValidClippingNumber:(NSNumber *)number inStore:(FlycutStore*)store {
    return ( ([number intValue] + 1) <= [store jcListCount] );
}

-(NSString *) clippingStringWithCount:(int)count {
	return [self clippingStringWithCount:count inStore:clippingStore];
}

-(NSString *) clippingStringWithCount:(int)count inStore:(FlycutStore*)store {
    if ( [self isValidClippingNumber:[NSNumber numberWithInt:count] inStore:store] ) {
        return [store clippingContentsAtPosition:count];
    } else { // It fails -- we shouldn't be passed this, but...
        return @"";
    }
}

-(void) registerOrDeregisterICloudSync
{
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"syncSettingsViaICloud"] ) {
		[MJCloudKitUserDefaultsSync startWithKeyMatchList:settingsSyncList
								  withContainerIdentifier:@"iCloud.com.mark-a-jerde.Flycut"];
	}
	else {
		[MJCloudKitUserDefaultsSync stopForKeyMatchList:settingsSyncList];
	}

	BOOL syncClippings = [[NSUserDefaults standardUserDefaults] boolForKey:@"syncClippingsViaICloud"];
	BOOL changedSyncClippings = ( ![[NSUserDefaults standardUserDefaults] objectForKey:@"previousSyncClippingsViaICloud"]
								 || syncClippings != [[NSUserDefaults standardUserDefaults] boolForKey:@"previousSyncClippingsViaICloud"] );

	if ( changedSyncClippings )
		[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:syncClippings]
												 forKey:@"previousSyncClippingsViaICloud"];

	// We will enable / disable regardless of changedSyncClippings because this gets called at app launch, where the feature was previously enabled but needs to be registered.
	if ( syncClippings ) {
		if ( changedSyncClippings )
			firstClippingsSyncAfterEnabling = YES;

		[MJCloudKitUserDefaultsSync removeNotificationsFor:MJSyncNotificationChanges forTarget:self];
		[MJCloudKitUserDefaultsSync addNotificationFor:MJSyncNotificationChanges withSelector:@selector(checkPreferencesChanges:) withTarget: self];

		[MJCloudKitUserDefaultsSync removeNotificationsFor:MJSyncNotificationConflicts forTarget:self];
		[MJCloudKitUserDefaultsSync addNotificationFor:MJSyncNotificationConflicts withSelector:@selector(checkPreferencesConflicts:) withTarget: self];

		[MJCloudKitUserDefaultsSync removeNotificationsFor:MJSyncNotificationSaveSuccess forTarget:self];
		[MJCloudKitUserDefaultsSync addNotificationFor:MJSyncNotificationSaveSuccess withSelector:@selector(checkPreferencesSaveSuccess:) withTarget: self];

		[MJCloudKitUserDefaultsSync startWithKeyMatchList:@[@"store"]
								  withContainerIdentifier:@"iCloud.com.mark-a-jerde.Flycut"];
	}
	else {
		[MJCloudKitUserDefaultsSync removeNotificationsFor:MJSyncNotificationChanges forTarget:self];

		[MJCloudKitUserDefaultsSync stopForKeyMatchList:@[@"store"]];
	}
}

-(NSDictionary*) checkPreferencesChanges:(NSDictionary*)changes
{
	if ( [changes valueForKey:@"store"] )
	{
		[self integrateAllStores];
	}
	return nil;
}

-(void) integrateAllStores
{
	DLog(@"integrating stores");
	inhibitSaveEngineAfterListModification = YES;

	[self integrateStoreAtKey:@"jcList" into:clippingStore descriptiveName:@""];
	// It is possible that the user would disable sync rather than merge the main clippings store.  They would have a poor user experience if they were then asked the same question about the favorites store after believing that they had disabled sync, so check setting before integrating.
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"syncClippingsViaICloud"] )
		[self integrateStoreAtKey:@"favoritesList" into:favoritesStore descriptiveName:@"favorites "];
	DLog(@"integrating stores complete");

	inhibitSaveEngineAfterListModification = NO;
	firstClippingsSyncAfterEnabling = NO;
	[self actionAfterListModification];
}

-(void) integrateStoreAtKey:(NSString*)listKey into:(FlycutStore*)store descriptiveName:(NSString*)name
{
	FlycutStore *newContent = [self allocInitFlycutStoreRemembering:[clippingStore rememberNum]];
	NSDictionary *loadDict = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"store"] copy];

	if ( loadDict && [self loadEngineFrom:loadDict key:listKey into:newContent] )
	{
		BOOL mergeLists = NO;
		if ( firstClippingsSyncAfterEnabling )
		{
			if ( 0 == [store jcListCount] )
			{
				// Just accept whatever iCloud has.
				[store clearInsertionJournalCount:[[store insertionJournal] count]];
				[store clearDeletionJournalCount:[[store deletionJournal] count]];
			}
			else if ( 0 == [newContent jcListCount] )
			{
				// We have something.  iCloud has nothing.  Ignore iCloud this time.
				[newContent release];
				[self actionAfterListModification]; // To overwrite what sync put in the defaults.
				return;
			}
			else
			{
				int newCount = [newContent jcListCount];
				int ourCount = [store jcListCount];
				int newDistinct = 0;
				int ourDistinct = 0;
				for ( int i = 0 ; i < newCount ; i++ )
				{
					if ( 0 > [store indexOfClipping:[newContent clippingAtPosition:i]] )
					{
						newDistinct++;
					}
				}
				for ( int i = 0 ; i < ourCount ; i++ )
				{
					if ( 0 > [newContent indexOfClipping:[store clippingAtPosition:i]] )
					{
						ourDistinct++;
					}
				}

				BOOL promptUser = NO;
				if ( 0 == ourDistinct )
				{
					// Just accept whatever iCloud has.
					[store clearInsertionJournalCount:[[store insertionJournal] count]];
					[store clearDeletionJournalCount:[[store deletionJournal] count]];
				}
				else if ( 0 == newDistinct )
				{
					// We have something.  iCloud has nothing.  Ignore iCloud this time.
					[newContent release];
					[self actionAfterListModification]; // To overwrite what sync put in the defaults.
					return;
				}
				else
				{
					// Policy: For sake of user experience, the user will not be asked to merge or overwrite if one is a superset of the other and they have just said that they want sync.  Assume they meant, "I want sync and I want it to include all content."
					promptUser = YES;
				}

				while ( promptUser )
				{
					promptUser = NO;

					NSString *choice = [self delegateAlertWithMessageText:@"First Sync"
														  informationText:[NSString stringWithFormat:@"Flycut found %i %@clipping%@ shared by both iCloud and this device, %i only in iCloud, and \%i only on this device.  How can I handle these for you?",
																		   (ourCount-ourDistinct),
																		   name,
																		   ((ourCount-ourDistinct)!=1?@"s":@""),
																		   newDistinct,ourDistinct]
															 buttonsTexts:@[@"Merge Lists",
																			@"Overwrite Device List",
																			@"Overwrite iCloud List",
																			@"Disable Sync"]];

					if (!choice )
					{
						// This most likely means the UI wasn't implemented, so cover it with merge.
						choice = @"Merge Lists";
					}

					if ( [choice isEqualToString:@"Merge Lists"] )
					{
						mergeLists = YES;
					}
					else if ( [choice isEqualToString:@"Disable Sync"] )
					{
						[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:NO]
																 forKey:@"syncClippingsViaICloud"];
						[newContent release];
						[self registerOrDeregisterICloudSync];
						[self actionAfterListModification]; // To overwrite what sync put in the defaults.
						return;
					}
					else
					{
						NSString *okCancel = [self delegateAlertWithMessageText:@"Warning"
																informationText:[NSString stringWithFormat:@"%@ will cause clippings to be lost!", choice]
																   buttonsTexts:@[@"Ok", @"Cancel"]];

						if ( [okCancel isEqualToString:@"Ok"] )
						{
							if ( [choice isEqualToString:@"Overwrite Device List"] )
							{
								// Just accept whatever iCloud has.
								[store clearInsertionJournalCount:[[store insertionJournal] count]];
								[store clearDeletionJournalCount:[[store deletionJournal] count]];
							}
							else if ( [choice isEqualToString:@"Overwrite iCloud List"] )
							{
								// Ignore iCloud this time.
								[newContent release];
								[self actionAfterListModification]; // To overwrite what sync put in the defaults.
								return;
							}
							else
							{
								// This should be impossible, so cover it with disabling sync.
								[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:NO] forKey:@"syncClippingsViaICloud"];
								[newContent release];
								[self registerOrDeregisterICloudSync];
								[self actionAfterListModification]; // To overwrite what sync put in the defaults.
								return;
							}
						}
						else
						{
							promptUser = YES;
						}
					}
				}
			}
		}
		int newCount = [newContent jcListCount];
		int offsetForMerge = 0;
		for ( int i = 0 ; i < newCount ; i++ )
		{
			FlycutClipping *newClipping = [newContent clippingAtPosition:i];
			if ( i >= [store jcListCount] )
			{
				// Clipping was beyond the end of the store, so just add it.
				[self integrateInsertClipping:newClipping toStore:store atIndex:(i+offsetForMerge) withMerge:mergeLists];
			}
			else if ( ![newClipping isEqual:[store clippingAtPosition:(i+offsetForMerge)]] )
			{
				BOOL contentAtThisStorePositionNotInNewContent = (i+offsetForMerge) < [store jcListCount] && [newContent indexOfClipping:[store clippingAtPosition:(i+offsetForMerge)]] < 0;
				int firstIndex = [store indexOfClipping:newClipping];
				if ( firstIndex < 0 && [[store deletionJournal] containsObject:newClipping] )
				{
					// Clipping was deleted locally, so delete from the new content and move on.
					[newContent clearItem:i];
					i--;
					newCount--;
				}
				else if ( firstIndex < 0 )
				{
					// Clipping wasn't previously in the store, so just add it.
					if ( mergeLists && contentAtThisStorePositionNotInNewContent )
					{
						// Give priority to local items so they end up at the top of the list.
						// Look to the next store item.
						offsetForMerge++;
						// While checking this newContent item again.
						i--;
					}
					else
					{
						[self integrateInsertClipping:newClipping toStore:store atIndex:(i+offsetForMerge) withMerge:mergeLists];
					}
				}
				else if ( contentAtThisStorePositionNotInNewContent )
				{
					// Contents in the store at this position didn't exist in the newContent.  Handle deletion.
					if ( mergeLists
						|| [[store insertionJournal] containsObject:[store clippingAtPosition:(i+offsetForMerge)]] )
					{
						// Look to the next store item.
						offsetForMerge++;
						// While checking this newContent item again.
						i--;
					}
					else
					{
						[store clearItem:(i+offsetForMerge)];
						i--;
					}
				}
				else if ( [store removeDuplicates] )
				{
					if ( i < firstIndex )
						[store clippingMoveFrom:firstIndex To:(i+offsetForMerge)];
					else
					{
						// This can only happen if the remote store allowed duplicates and we do not.  Just delete from the new content and move on.
						[newContent clearItem:i];
						i--;
						newCount--;
					}
				}
				else
				{
					[self integrateInsertClipping:newClipping toStore:store atIndex:(i+offsetForMerge) withMerge:mergeLists];
				}
			}
		}
		while ( [store jcListCount] > newCount + offsetForMerge )
			[store clearItem:(newCount + offsetForMerge)];

#ifdef DEBUG
		if ( !mergeLists )
		{
			[newContent release];
			newContent = [self allocInitFlycutStoreRemembering:[clippingStore rememberNum]];
			[self loadEngineFrom:loadDict key:listKey into:newContent];
			newCount = [newContent jcListCount];
			if ( newCount != [store jcListCount] )
				NSLog(@"Error in integrateStoreAtKey with mismatching after counts!");
			else
			{
				for ( int i = 0 ; i < newCount ; i++ )
				{
					if ( ![[store clippingAtPosition:i] isEqual:[newContent clippingAtPosition:i]] )
						NSLog(@"Error in integrateStoreAtKey with mismatching clippings at index %i!", i);
				}
			}
		}
#endif
	}

	[newContent release];
}

-(void) integrateInsertClipping:(FlycutClipping*)clipping toStore:(FlycutStore*)store atIndex:(int)index withMerge:(BOOL)mergeLists
{
	[clipping setDisplayLength:displayLength];

	if ( mergeLists && [store jcListCount] == [store rememberNum] )
	{
		// Grow the rememberNum if needed in merge.
		int newRememberNum = [store rememberNum] + 1;
		[store setRememberNum:newRememberNum];
		if ( store == favoritesStore )
		{
			[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:newRememberNum]
													 forKey:@"favoritesRememberNum"];
		}
		else
		{
			[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:newRememberNum]
													 forKey:@"rememberNum"];
		}
	}

	[store insertClipping:clipping atIndex:index];
}

-(NSDictionary*) checkPreferencesConflicts:(NSDictionary*)changes
{
	NSMutableDictionary *corrections = nil;
	if ( [changes valueForKey:@"store"] )
	{
		// Load the version that the other party pushed.
		[[NSUserDefaults standardUserDefaults] setObject:[changes valueForKey:@"store"][2] forKey:@"store"];

		// Integrate stores to apply journaled changes to conflict resolution.
		[self integrateAllStores];

		// Load the resolution into corrections.
		if ( !corrections )
			corrections = [[NSMutableDictionary alloc] init];
		corrections[@"store"] = [[NSUserDefaults standardUserDefaults] objectForKey: @"store"];
	}
	return corrections;
}

-(NSDictionary*) checkPreferencesSaveSuccess:(NSDictionary*)changes
{
	if ( [changes valueForKey:@"store"] )
	{
		[clippingStore pruneJournals];
		[favoritesStore pruneJournals];
	}
	return nil;
}

-(void) checkCloudKitUpdates
{
	[MJCloudKitUserDefaultsSync checkCloudKitUpdates];
}

-(bool) loadEngineFrom:(NSDictionary*)loadDict key:(NSString*)listKey into:(FlycutStore*)store
{
	NSArray *savedJCList = [loadDict objectForKey:listKey];
	if ( [savedJCList isKindOfClass:[NSArray class]] ) {
		// There's probably a nicer way to prevent the range from going out of bounds, but this works.
		int rangeCap = [savedJCList count] < [store rememberNum] ? [savedJCList count] : [store rememberNum];
		NSRange loadRange = NSMakeRange(0, rangeCap);
		NSArray *toBeRestoredClips = [[[savedJCList subarrayWithRange:loadRange] reverseObjectEnumerator] allObjects];
		for( NSDictionary *aSavedClipping in toBeRestoredClips)
			[store addClipping:[aSavedClipping objectForKey:@"Contents"]
							  ofType:[aSavedClipping objectForKey:@"Type"]
				fromAppLocalizedName:[aSavedClipping objectForKey:@"AppLocalizedName"]
					fromAppBundleURL:[aSavedClipping objectForKey:@"AppBundleURL"]
						 atTimestamp:[[aSavedClipping objectForKey:@"Timestamp"] integerValue]];
		return YES;
	} else DLog(@"Not array");
	return NO;
}

-(bool) loadEngineFromPList
{
	NSDictionary *loadDict = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"store"] copy];

	if ( loadDict != nil ) {
		bool success = NO;
		success |= [self loadEngineFrom:loadDict key:@"jcList" into:clippingStore];
		success |= [self loadEngineFrom:loadDict key:@"favoritesList" into:favoritesStore];
		[loadDict release];
		return success;
	}
	return NO;
}

-(bool)setStackPositionToOneLessRecent
{
	stackPosition++;
	if ( [clippingStore jcListCount] > stackPosition ) {
		return YES;
	} else {
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"wraparoundBezel"] ) {
			stackPosition = 0;
			return YES;
		} else {
			stackPosition--;
		}
	}
	return NO;
}

-(bool)setStackPositionToOneMoreRecent
{
	stackPosition--;
	if ( stackPosition < 0 ) {
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"wraparoundBezel"] ) {
			stackPosition = [clippingStore jcListCount] - 1;
			return YES;
		} else {
			stackPosition = 0;
			return NO;
		}
	}
	if ( [clippingStore jcListCount] > stackPosition ) {
		return YES;
	}
	return NO;
}

-(FlycutClipping*)clippingAtStackPosition
{
    return [clippingStore clippingAtPosition:stackPosition];
}

- (void)saveStore:(FlycutStore *)store toKey:(NSString *)key onDict:(NSMutableDictionary *)saveDict {
    NSMutableArray *jcListArray = [NSMutableArray array];
    for ( int i = 0 ; i < [store jcListCount] ; i++ )
    {
        FlycutClipping *clipping = [store clippingAtPosition:i];
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     [clipping contents], @"Contents",
                                     [clipping type], @"Type",
                                     [NSNumber numberWithInt:i], @"Position",nil];

        NSString *val = [clipping appLocalizedName];
        if ( nil != val )
            [dict setObject:val forKey:@"AppLocalizedName"];

        val = [clipping appBundleURL];
        if ( nil != val )
            [dict setObject:val forKey:@"AppBundleURL"];

        int timestamp = [clipping timestamp];
        if ( timestamp > 0 )
            [dict setObject:[NSNumber numberWithInt:timestamp] forKey:@"Timestamp"];

        [jcListArray addObject:dict];
    }
    [saveDict setObject:jcListArray forKey:key];
	[store clearModifiedSinceLastSaveStore];
}

-(void) saveEngine {
	// saveEngine saves to NSUserDefaults.  If there have been no modifications, just skip this to avoid busy activity for any observers.
	if ( !([clippingStore modifiedSinceLastSaveStore]
		   || [favoritesStore modifiedSinceLastSaveStore]) )
		return;

    NSMutableDictionary *saveDict;
    saveDict = [NSMutableDictionary dictionaryWithCapacity:3];
    [saveDict setObject:@"0.7" forKey:@"version"];
    [saveDict setObject:[NSNumber numberWithInt:[[NSUserDefaults standardUserDefaults] integerForKey:@"rememberNum"]]
                 forKey:@"rememberNum"];
    [saveDict setObject:[NSNumber numberWithInt:[[NSUserDefaults standardUserDefaults] integerForKey:@"favoritesRememberNum"]]
                 forKey:@"favoritesRememberNum"];

	[saveTarget performSelector:saveSelector withObject:saveDict];

    [self saveStore:clippingStore toKey:@"jcList" onDict:saveDict];
    [self saveStore:favoritesStore toKey:@"favoritesList" onDict:saveDict];

    [[NSUserDefaults standardUserDefaults] setObject:saveDict forKey:@"store"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationWillTerminate {
	if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 1 ) {
		DLog(@"Saving on exit");
        [self saveEngine];
    } else {
        // Remove clips from store
        [[NSUserDefaults standardUserDefaults] setValue:[NSDictionary dictionary] forKey:@"store"];
        DLog(@"Saving preferences on exit");
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

-(NSArray *) previousIndexes:(int)howMany containing:(NSString*)search // This method is in newest-first order.
{
	return [clippingStore previousIndexes:howMany containing:search];
}

-(NSArray *) previousDisplayStrings:(int)howMany containing:(NSString*)search
{
	return [clippingStore previousDisplayStrings:howMany containing:search];
}

-(NSString*) delegateAlertWithMessageText:(NSString*)message informationText:(NSString*)information buttonsTexts:(NSArray*)buttons
{
	if ( self.delegate && [self.delegate respondsToSelector:@selector(alertWithMessageText:informationText:buttonsTexts:)] )
		return [self.delegate alertWithMessageText:message informationText:information buttonsTexts:buttons];
	return nil;
}

@end
