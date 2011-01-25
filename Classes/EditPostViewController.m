#import "EditPostViewController.h"
#import "WordPressAppDelegate.h"
#import "BlogDataManager.h"
#import "WPSegmentedSelectionTableViewController.h"
#import "WPNavigationLeftButtonView.h"
#import "CPopoverManager.h"

NSTimeInterval kAnimationDuration = 0.3f;

@implementation EditPostViewController

@synthesize selectionTableViewController, segmentedTableViewController;
@synthesize infoText, urlField, bookMarksArray, selectedLinkRange, currentEditingTextField, isEditing, initialLocation;
@synthesize editingDisabled, editCustomFields, statuses, isLocalDraft, normalTextFrame;
@synthesize textView, contentView, subView, textViewContentView, statusTextField, categoriesTextField, titleTextField;
@synthesize tagsTextField, textViewPlaceHolderField, tagsLabel, statusLabel, categoriesLabel, titleLabel, customFieldsEditButton;
@synthesize locationButton, locationSpinner, newCategoryBarButtonItem;
@synthesize editMode, apost;
@synthesize hasChanges, hasSaved, isVisible, isPublishing;

- (id)initWithPost:(AbstractPost *)aPost {
    NSString *nib;
    if (DeviceIsPad()) {
        nib = @"EditPostViewController-iPad";
    } else {
        nib = @"EditPostViewController";
    }
    
    if (self = [super initWithNibName:nib bundle:nil]) {
        self.apost = aPost;
    }
    
    return self;
}

- (Post *)post {
    if ([self.apost isKindOfClass:[Post class]]) {
        return (Post *)self.apost;
    } else {
        return nil;
    }
}

- (void)setPost:(Post *)aPost {
    self.apost = aPost;
}

- (UIViewAnimationOptions)directionFromView:(UIView *)old toView:(UIView *)new {
    if (old == editView)
        return UIViewAnimationOptionTransitionFlipFromRight;
    else
        return UIViewAnimationOptionTransitionFlipFromLeft;
}

- (void)switchToView:(UIView *)newView {
    newView.frame = currentView.frame;
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.5];
    NSMutableArray *toolbarItems = [NSMutableArray arrayWithArray:toolbar.items];
    if ([newView isEqual:editView]) {
        [UIView setAnimationTransition:UIViewAnimationTransitionFlipFromRight forView:contentView cache:YES];
        [toolbarItems replaceObjectAtIndex:0 withObject:settingsButton];
    } else {
        [UIView setAnimationTransition:UIViewAnimationTransitionFlipFromLeft forView:contentView cache:YES];
        [toolbarItems replaceObjectAtIndex:0 withObject:writeButton];
    }
    [toolbar setItems:[NSArray arrayWithArray:toolbarItems]];

    [currentView removeFromSuperview];
    [contentView addSubview:newView];

    [UIView commitAnimations];
    
    currentView = newView;
}

- (IBAction)switchToEdit {
    if (currentView != editView) {
        [self switchToView:editView];
    }
}

- (IBAction)switchToSettings {
    if (currentView != postSettingsController.view) {
        [self switchToView:postSettingsController.view];
    }
}

#pragma mark -
#pragma mark View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [FlurryAPI logEvent:@"EditPost"];

    postSettingsController = [[PostSettingsViewController alloc] initWithNibName:@"PostSettingsViewController" bundle:nil];
    postSettingsController.postDetailViewController = self;
    postSettingsController.view.frame = editView.frame;

	self.navigationItem.title = @"Write";
	statuses = [NSArray arrayWithObjects:@"Local Draft", @"Draft", @"Private", @"Pending Review", @"Published", nil];
	normalTextFrame = textView.frame;
		
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceDidRotate:) name:@"UIDeviceOrientationDidChangeNotification" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(save) name:@"EditPostViewShouldSave" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(publish) name:@"EditPostViewShouldPublish" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(newCategoryCreatedNotificationReceived:) name:WPNewCategoryCreatedAndUpdatedInBlogNotificationName object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(insertMediaAbove:) name:@"ShouldInsertMediaAbove" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(insertMediaBelow:) name:@"ShouldInsertMediaBelow" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeMedia:) name:@"ShouldRemoveMedia" object:nil];
	
    isTextViewEditing = NO;
    spinner = [[WPProgressHUD alloc] initWithLabel:@"Saving..."];
	hasSaved = NO;
    
    currentView = editView;
    tabPointer.hidden = YES;

    NSMutableArray *toolbarItems = [NSMutableArray arrayWithArray:toolbar.items];
    [toolbarItems removeObject:writeButton];
    [toolbar setItems:[NSArray arrayWithArray:toolbarItems]];

    if (iOs4OrGreater()) {
        self.view.backgroundColor = [UIColor scrollViewTexturedBackgroundColor];
    }
    if(self.editMode == kEditPost)
        [self refreshUIForCurrentPost];
	else if(self.editMode == kNewPost)
        [self refreshUIForCompose];
	else if (self.editMode == kAutorecoverPost) {
        [self refreshUIForCurrentPost];
        self.hasChanges = YES;
	}
    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if(self.editMode != kNewPost)
		self.editMode = kRefreshPost;
	
	isVisible = YES;
    
	[self refreshButtons];
	
	self.navigationItem.title = @"Write";
}

- (void)viewWillDisappear:(BOOL)animated {	
	if(self.editMode != kNewPost)
		self.editMode = kRefreshPost;
	isVisible = NO;
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[titleTextField resignFirstResponder];
	[textView resignFirstResponder];
    [super viewWillDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
	if(DeviceIsPad() == YES)
		return YES;
	else
		return NO;
}

- (void)disableInteraction {
	editingDisabled = YES;
}

#pragma mark -

- (void)dismissEditView {
	if (DeviceIsPad() == NO) {
        WordPressAppDelegate *appDelegate = (WordPressAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appDelegate.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissModalViewControllerAnimated:YES];
		[[BlogDataManager sharedDataManager] loadDraftTitlesForCurrentBlog];
		[[BlogDataManager sharedDataManager] loadPostTitlesForCurrentBlog];
		
		UIViewController *theTopVC = [[WordPressAppDelegate sharedWordPressApp].masterNavigationController topViewController];
		if ([theTopVC respondsToSelector:@selector(reselect)])
			[theTopVC performSelector:@selector(reselect)];
	}
    
	[FlurryAPI logEvent:@"EditPost#dismissEditView"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PostEditorDismissed" object:self];
}


- (void)refreshButtons {
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self
                                                                                  action:@selector(cancelView:)];
    self.navigationItem.leftBarButtonItem = cancelButton;
    [cancelButton release];
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] init];
    saveButton.title = @"Save";
    saveButton.target = self;
    saveButton.style = UIBarButtonItemStyleDone;
    saveButton.action = @selector(saveAction:);
    
    if(![self.post hasRemote]) {
        if ([self.post.status isEqualToString:@"publish"]) {
            saveButton.title = @"Publish";
        } else {
            saveButton.title = @"Save";
        }
    } else {
        saveButton.title = @"Update";
    }
    self.navigationItem.rightBarButtonItem = saveButton;
    
    [saveButton release];
}

- (BOOL)isPostPublished {
	BOOL result = NO;
	if(isLocalDraft == YES) {
		result = NO;
	}
	else {
		BlogDataManager *dm = [BlogDataManager sharedDataManager];
		NSString *status = [dm statusDescriptionForStatus:[dm.currentPost valueForKey:@"post_status"] fromBlog:dm.currentBlog];
		
		if([[status lowercaseString] isEqualToString:@"published"])
			result = YES;
		else
			result = NO;
	}
	
	return result;
}


- (void)refreshUIForCompose {
	self.navigationItem.title = @"Write";
    titleTextField.text = @"";
    textView.text = @"";
    textViewPlaceHolderField.hidden = NO;
	self.isLocalDraft = YES;
}

- (void)refreshUIForCurrentPost {
    if ([self.apost.postTitle length] > 0) {
        self.navigationItem.title = self.apost.postTitle;
    }
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                style:UIBarButtonItemStyleBordered target:nil action:nil];

    titleTextField.text = self.apost.postTitle;
    if (self.post) {
        // FIXME: tags should be an array/set of Tag objects
        tagsTextField.text = self.post.tags;
        categoriesTextField.text = [self.post categoriesText];
    }
    
    if(self.apost.content == nil) {
        textViewPlaceHolderField.hidden = NO;
        textView.text = @"";
    }
    else {
        textViewPlaceHolderField.hidden = YES;
        textView.text = self.apost.content;
    }

	// workaround for odd text view behavior on iPad
	[textView setContentOffset:CGPointZero animated:NO];
}

- (void)populateSelectionsControllerWithCategories {
    if (segmentedTableViewController == nil)
        segmentedTableViewController = [[WPSegmentedSelectionTableViewController alloc] initWithNibName:@"WPSelectionTableViewController" bundle:nil];
	
	NSArray *cats = [self.post.blog.categories allObjects];
	NSArray *selObject;
	
    selObject = [self.post.categories allObjects];
	
    [segmentedTableViewController populateDataSource:cats    //datasorce
									   havingContext:kSelectionsCategoriesContext
									 selectedObjects:selObject
									   selectionType:kCheckbox
										 andDelegate:self];
	
    segmentedTableViewController.title = @"Categories";
    segmentedTableViewController.navigationItem.rightBarButtonItem = newCategoryBarButtonItem;

    if (isNewCategory != YES) {
		if (DeviceIsPad() == YES) {
            UINavigationController *navController;
            if (segmentedTableViewController.navigationController) {
                navController = segmentedTableViewController.navigationController;
            } else {
                navController = [[[UINavigationController alloc] initWithRootViewController:segmentedTableViewController] autorelease];
            }
 			UIPopoverController *popover = [[[NSClassFromString(@"UIPopoverController") alloc] initWithContentViewController:navController] autorelease];
            popover.delegate = self;			CGRect popoverRect = [self.view convertRect:[categoriesTextField frame] fromView:[categoriesTextField superview]];
			popoverRect.size.width = MIN(popoverRect.size.width, 100); // the text field is actually really big
			[popover presentPopoverFromRect:popoverRect inView:self.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
			[[CPopoverManager instance] setCurrentPopoverController:popover];
		}
		else {
			WordPressAppDelegate *delegate = (WordPressAppDelegate *)[[UIApplication sharedApplication] delegate];
			self.editMode = kEditPost;
			[delegate.navigationController pushViewController:segmentedTableViewController animated:YES];
		}
    }
	
    isNewCategory = NO;
}

- (void)refreshStatus {
	if(isLocalDraft == YES) {
		statusTextField.text = @"Local Draft";
	}
	else {
		statusTextField.text = self.post.statusTitle;
	}
}

- (void)populateSelectionsControllerWithStatuses {
    if (selectionTableViewController == nil)
        selectionTableViewController = [[WPSelectionTableViewController alloc] initWithNibName:@"WPSelectionTableViewController" bundle:nil];
	
    NSArray *dataSource = [self.post availableStatuses];
	
    NSString *curStatus = self.post.statusTitle;
	
    NSArray *selObject = (curStatus == nil ? [NSArray array] : [NSArray arrayWithObject:curStatus]);
	
    [selectionTableViewController populateDataSource:dataSource
									   havingContext:kSelectionsStatusContext
									 selectedObjects:selObject
									   selectionType:kRadio
										 andDelegate:self];
	
    selectionTableViewController.title = @"Status";
    selectionTableViewController.navigationItem.rightBarButtonItem = nil;
	if (DeviceIsPad() == YES) {
		UINavigationController *navController = [[[UINavigationController alloc] initWithRootViewController:selectionTableViewController] autorelease];
		UIPopoverController *popover = [[[NSClassFromString(@"UIPopoverController") alloc] initWithContentViewController:navController] autorelease];
		CGRect popoverRect = [self.view convertRect:[statusTextField frame] fromView:[statusTextField superview]];
		popoverRect.size.width = MIN(popoverRect.size.width, 100);
		[popover presentPopoverFromRect:popoverRect inView:self.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
		[[CPopoverManager instance] setCurrentPopoverController:popover];
	}
	else {
		WordPressAppDelegate *delegate = (WordPressAppDelegate *)[[UIApplication sharedApplication] delegate];
		[delegate.navigationController pushViewController:selectionTableViewController animated:YES];
	}
    [selectionTableViewController release], selectionTableViewController = nil;
}

- (void)selectionTableViewController:(WPSelectionTableViewController *)selctionController completedSelectionsWithContext:(void *)selContext selectedObjects:(NSArray *)selectedObjects haveChanges:(BOOL)isChanged {
    if (!isChanged) {
        [selctionController clean];
        return;
    }

    if (selContext == kSelectionsStatusContext) {
        NSString *curStatus = [selectedObjects lastObject];
        self.post.statusTitle = curStatus;
        statusTextField.text = curStatus;
    }
    
    if (selContext == kSelectionsCategoriesContext) {
        NSLog(@"selected categories: %@", selectedObjects);
        NSLog(@"post: %@", self.post);
        self.post.categories = [NSMutableSet setWithArray:selectedObjects];
        categoriesTextField.text = [self.post categoriesText];
    }
	
    [selctionController clean];
    self.hasChanges = YES;
	[self refreshButtons];
}

- (void)newCategoryCreatedNotificationReceived:(NSNotification *)notification {
    if ([segmentedTableViewController curContext] == kSelectionsCategoriesContext) {
        isNewCategory = YES;
        [self populateSelectionsControllerWithCategories];
    }
}

- (IBAction)showAddNewCategoryView:(id)sender
{
    WPAddCategoryViewController *addCategoryViewController = [[WPAddCategoryViewController alloc] initWithNibName:@"WPAddCategoryViewController" bundle:nil];
    addCategoryViewController.blog = self.post.blog;
	if (DeviceIsPad() == YES) {
        [segmentedTableViewController pushViewController:addCategoryViewController animated:YES];
 	} else {
		UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:addCategoryViewController];
		[segmentedTableViewController presentModalViewController:nc animated:YES];
		[nc release];
	}
    [addCategoryViewController release];
}

- (void)endEditingAction:(id)sender {
    [titleTextField resignFirstResponder];
    [tagsTextField resignFirstResponder];
    [textView resignFirstResponder];
}

- (void)discard {
    [FlurryAPI logEvent:@"Post#actionSheet_discard"];
    hasChanges = NO;
    
	// TODO: remove the mediaViewController notifications - this is pretty kludgy
    [self.apost.original deleteRevision];
    self.apost = nil; // Just in case
    [self dismissEditView];
}

- (IBAction)saveAction:(id)sender {
    self.apost.postTitle = titleTextField.text;
    self.apost.content = textView.text;
    
    [self.view endEditing:YES];
    [self.apost.original applyRevision];
    [self.apost.original upload];
    [self dismissEditView];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([actionSheet tag] == 201) {
        if (buttonIndex == 0) {
            [self discard];
        }
        
        if (buttonIndex == 1) {
            [self saveAction:self];
        }
    }
    
    WordPressAppDelegate *appDelegate = (WordPressAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appDelegate setAlertRunning:NO];
}

- (IBAction)cancelView:(id)sender {
    [FlurryAPI logEvent:@"EditPost#cancelView"];
    if (!hasChanges) {
        [self discard];
        return;
    }
    [FlurryAPI logEvent:@"EditPost#cancelView(actionSheet)"];
	[postSettingsController endEditingAction:nil];
	[self endEditingAction:nil];
    
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"You have unsaved changes."
                                                             delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Discard"
                                                    otherButtonTitles:nil];
    actionSheet.tag = 201;
    actionSheet.actionSheetStyle = UIActionSheetStyleAutomatic;
    [actionSheet showInView:self.view];
    WordPressAppDelegate *appDelegate = (WordPressAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appDelegate setAlertRunning:YES];
    
    [actionSheet release];
}

- (IBAction)endTextEnteringButtonAction:(id)sender {
    [textView resignFirstResponder];
	if (DeviceIsPad() == NO) {
		//		if((self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft) || (self.interfaceOrientation == UIInterfaceOrientationLandscapeRight))
		//			[[UIDevice currentDevice] setOrientation:UIInterfaceOrientationPortrait];
	}
}

- (IBAction)showCategoriesViewAction:(id)sender {
	//[self showEditPostModalViewWithAnimation:YES];
    [self populateSelectionsControllerWithCategories];
	
}

- (IBAction)showStatusViewAction:(id)sender {
    [self populateSelectionsControllerWithStatuses];
}

- (void)resignTextView {
	[textView resignFirstResponder];
}

//code to append http:// if protocol part is not there as part of urlText.
- (NSString *)validateNewLinkInfo:(NSString *)urlText {
    NSArray *stringArray = [NSArray arrayWithObjects:@"http:", @"ftp:", @"https:", nil];
    int i, count = [stringArray count];
    BOOL searchRes = NO;
	
    for (i = 0; i < count; i++) {
        NSString *searchString = [stringArray objectAtIndex:i];
		
        if (searchRes = [urlText hasPrefix:[searchString capitalizedString]])
            break;else if (searchRes = [urlText hasPrefix:[searchString lowercaseString]])
				break;else if (searchRes = [urlText hasPrefix:[searchString uppercaseString]])
					break;
    }
	
    NSString *returnStr;
	
    if (searchRes)
        returnStr = [NSString stringWithString:urlText];else
			returnStr = [NSString stringWithFormat:@"http://%@", urlText];
	
    return returnStr;
}

- (void)showLinkView {
    UIAlertView *addURLSourceAlert = [[UIAlertView alloc] initWithFrame:CGRectMake(0, 0, 0, 0.0)];
    infoText = [[UITextField alloc] initWithFrame:CGRectMake(12.0, 48.0, 260.0, 29.0)];
    urlField = [[UITextField alloc] initWithFrame:CGRectMake(12.0, 82.0, 260.0, 29.0)];
    infoText.placeholder = @"Text to be linked";
    urlField.placeholder = @"Link URL";
    //infoText.enabled = YES;
	
    infoText.autocapitalizationType = UITextAutocapitalizationTypeNone;
    urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    infoText.borderStyle = UITextBorderStyleRoundedRect;
    urlField.borderStyle = UITextBorderStyleRoundedRect;
    infoText.keyboardAppearance = UIKeyboardAppearanceAlert;
    urlField.keyboardAppearance = UIKeyboardAppearanceAlert;
	infoText.keyboardType = UIKeyboardTypeDefault;
	urlField.keyboardType = UIKeyboardTypeURL;
    [addURLSourceAlert addButtonWithTitle:@"Cancel"];
    [addURLSourceAlert addButtonWithTitle:@"Save"];
    addURLSourceAlert.title = @"Make a Link\n\n\n\n";
    addURLSourceAlert.delegate = self;
    [addURLSourceAlert addSubview:infoText];
    [addURLSourceAlert addSubview:urlField];
    [infoText becomeFirstResponder];
	
	//deal with rotation
	if ((self.interfaceOrientation == UIDeviceOrientationLandscapeLeft)
		|| (self.interfaceOrientation == UIDeviceOrientationLandscapeRight))
	{
		CGAffineTransform upTransform = CGAffineTransformMakeTranslation(0.0, 80.0);
		[addURLSourceAlert setTransform:upTransform];
	}else{
		CGAffineTransform upTransform = CGAffineTransformMakeTranslation(0.0, 140.0);
		[addURLSourceAlert setTransform:upTransform];
	}
	
    //[addURLSourceAlert setTransform:upTransform];
    [addURLSourceAlert setTag:2];
    [addURLSourceAlert show];
    [addURLSourceAlert release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    WordPressAppDelegate *delegate = [[UIApplication sharedApplication] delegate];
	
    if ([alertView tag] == 1) {
        if (buttonIndex == 1)
            [self showLinkView];else {
				dismiss = YES;
				[textView touchesBegan:nil withEvent:nil];
				[delegate setAlertRunning:NO];
			}
    }
	
    if ([alertView tag] == 2) {
        if (buttonIndex == 1) {
            if ((urlField.text == nil) || ([urlField.text isEqualToString:@""])) {
                [delegate setAlertRunning:NO];
                return;
            }
			
            if ((infoText.text == nil) || ([infoText.text isEqualToString:@""]))
                infoText.text = urlField.text;
			
            NSString *commentsStr = textView.text;
            NSRange rangeToReplace = [self selectedLinkRange];
            NSString *urlString = [self validateNewLinkInfo:urlField.text];
            NSString *aTagText = [NSString stringWithFormat:@"<a href=\"%@\">%@</a>", urlString, infoText.text];;
            textView.text = [commentsStr stringByReplacingOccurrencesOfString:[commentsStr substringWithRange:rangeToReplace] withString:aTagText options:NSCaseInsensitiveSearch range:rangeToReplace];
        }
		
        dismiss = YES;
        [delegate setAlertRunning:NO];
        [textView touchesBegan:nil withEvent:nil];
    }
	
    return;
}

#pragma mark TextView & TextField Delegates

- (void)showDoneButton {
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone
                                                                  target:self action:@selector(endTextEnteringButtonAction:)];
    self.navigationItem.leftBarButtonItem = doneButton;
    self.navigationItem.rightBarButtonItem = nil;
    [doneButton release];
}

- (void)textViewDidChangeSelection:(UITextView *)aTextView {
    if (!isTextViewEditing) {
        isTextViewEditing = YES;
		
		if (DeviceIsPad() == NO) {
            [self showDoneButton];
		}
    }
}

- (void)textViewDidBeginEditing:(UITextView *)aTextView {
    isEditing = YES;
	if([textView.text isEqualToString:kTextViewPlaceholder] == YES) {
		textView.text = @"";
	}
	
	[textView setTextColor:[UIColor blackColor]];
	[self positionTextView:nil];
	
    dismiss = NO;
	
    if (!isTextViewEditing) {
        isTextViewEditing = YES;
		
 		if (DeviceIsPad() == NO) {
            [self showDoneButton];
		}
    }
}

//replace "&nbsp" with a space @"&#160;" before Apple's broken TextView handling can do so and break things
//this enables the "http helper" to work as expected
//important is capturing &nbsp BEFORE the semicolon is added.  Not doing so causes a crash in the textViewDidChange method due to array overrun
- (BOOL)textView:(UITextView *)aTextView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
	
	//if nothing has been entered yet, return YES to prevent crash when hitting delete
    if (text.length == 0) {
		return YES;
    }
	
    // create final version of textView after the current text has been inserted
    NSMutableString *updatedText = [[NSMutableString alloc] initWithString:aTextView.text];
    [updatedText insertString:text atIndex:range.location];
	
    NSRange replaceRange = range, endRange = range;
	
    if (text.length > 1) {
        // handle paste
        replaceRange.length = text.length;
    } else {
        // handle normal typing
        replaceRange.length = 6;  // length of "&#160;" is 6 characters
        replaceRange.location -= 5; // look back one characters (length of "&#160;" minus one)
    }
	
    // replace "&nbsp" with "&#160;" for the inserted range
    int replaceCount = [updatedText replaceOccurrencesOfString:@"&nbsp" withString:@"&#160;" options:NSCaseInsensitiveSearch range:replaceRange];
	
    if (replaceCount > 0) {
        // update the textView's text
        aTextView.text = updatedText;
		
        // leave cursor at end of inserted text
        endRange.location += text.length + replaceCount * 1; // length diff of "&nbsp" and "&#160;" is 1 character
		
        [updatedText release];
		
        // let the textView know that it should ingore the inserted text
        return NO;
    }
	
    [updatedText release];
	
    // let the textView know that it should handle the inserted text
    return YES;
}

- (void)textViewDidChange:(UITextView *)aTextView {
	[self setHasChanges:YES];
	
    if (dismiss == YES) {
        dismiss = NO;
        return;
    }
	
    NSRange range = [aTextView selectedRange];
    NSArray *stringArray = [NSArray arrayWithObjects:@"http:", @"ftp:", @"https:", @"www.", nil];
	//NSString *str = [[aTextView text]stringByReplacingOccurrencesOfString: @"&nbsp;" withString: @"&#160"];
    NSString *str = [aTextView text];
    int i, j, count = [stringArray count];
    BOOL searchRes = NO;
	
    for (j = 4; j <= 6; j++) {
        if (range.location < j)
            return;
		
        NSRange subStrRange;
		// subStrRange.location = range.location - j;
		//I took this out because adding &nbsp; to the post caused a mismatch between the length of the string from the text field and range.location
		//both should be equal, but the OS/Cocoa interprets &nbsp; as ONE space, not 6.
		//This caused NSString *subStr = [str substringWithRange:subStrRange]; to fail if the user entered &nbsp; in the post
		//subStrRange.location = str.length -j;
		subStrRange.location = range.location - j;
        subStrRange.length = j;
        [self setSelectedLinkRange:subStrRange];
		
		NSString *subStr = [str substringWithRange:subStrRange];
		
		for (i = 0; i < count; i++) {
			NSString *searchString = [stringArray objectAtIndex:i];
			
			if (searchRes = [subStr isEqualToString:[searchString capitalizedString]])
				break;else if (searchRes = [subStr isEqualToString:[searchString lowercaseString]])
					break;else if (searchRes = [subStr isEqualToString:[searchString uppercaseString]])
						break;
		}
		
		if (searchRes)
			break;
	}
	
    if (searchRes && dismiss != YES) {
        [textView resignFirstResponder];
        UIAlertView *linkAlert = [[UIAlertView alloc] initWithTitle:@"Make a Link" message:@"Would you like help making a link?" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Make a Link", nil];
        [linkAlert setTag:1];  // for UIAlertView Delegate to handle which view is popped.
        [linkAlert show];
        WordPressAppDelegate *delegate = [[UIApplication sharedApplication] delegate];
        [delegate setAlertRunning:YES];
        [linkAlert release];
    }
	else {
		[textView scrollRangeToVisible:textView.selectedRange];
	}	
}

- (void)textViewDidEndEditing:(UITextView *)aTextView {
	currentEditingTextField = nil;
	textView.frame = normalTextFrame;
	
	if([textView.text isEqualToString:@""] == YES) {
		textView.text = kTextViewPlaceholder;
		[textView setTextColor:[UIColor lightGrayColor]];
	}
	else {
		[textView setTextColor:[UIColor blackColor]];
	}

	
    isEditing = NO;
    dismiss = NO;
	
    if (isTextViewEditing) {
        isTextViewEditing = NO;
		[self positionTextView:nil];
		
        NSString *text = aTextView.text;
        self.post.content = text;
		
		if (DeviceIsPad() == NO) {
            [self refreshButtons];
		}
    }
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
	if (DeviceIsPad() == YES) {
		if (textField == categoriesTextField) {
			[self populateSelectionsControllerWithCategories];
			return NO;
		}
		else if (textField == statusTextField) {
			[self populateSelectionsControllerWithStatuses];
			return NO;
		}
	}
	return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField {
	return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.currentEditingTextField = textField;
	
    if (self.navigationItem.leftBarButtonItem.style == UIBarButtonItemStyleDone) {
        [self textViewDidEndEditing:textView];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.currentEditingTextField = nil;
	
    if (textField == titleTextField) {
        self.post.postTitle = textField.text;
        
        // FIXME: this should be -[PostsViewController updateTitle]
        if ([self.post.postTitle length] > 0) {
            self.navigationItem.title = self.post.postTitle;
        } else {
            self.navigationItem.title = @"Write";
        }

    }
	else if (textField == tagsTextField)
        self.post.tags = tagsTextField.text;
    
    [self.post autosave];
}

- (void)positionTextView:(NSDictionary *)keyboardInfo {
	CGFloat animationDuration = 0.3;
	UIViewAnimationCurve curve = 0.3;
	if(keyboardInfo != nil) {
		animationDuration = [[keyboardInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
		
		curve = [[keyboardInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] floatValue];
	}
		
	[UIView beginAnimations:nil context:nil];
	[UIView setAnimationCurve:curve];
	[UIView setAnimationDuration:animationDuration];
	CGRect keyboardFrame;
	
	// Reposition TextView for editing mode or normal mode based on device and orientation
	
	if(isEditing) {
		// Editing mode
		
		// Save time: Uncomment this line when you're debugging UITextView positioning
		//textView.backgroundColor = [UIColor blueColor];
		
		// iPad
		if(DeviceIsPad() == YES) {
			if ((self.interfaceOrientation == UIDeviceOrientationLandscapeLeft)
				|| (self.interfaceOrientation == UIDeviceOrientationLandscapeRight)) {
				// Landscape
				keyboardFrame = CGRectMake(0, 0, textView.frame.size.width, 350);
				
				[textView setFrame:keyboardFrame];
			}
			else {
				// Portrait
				keyboardFrame = CGRectMake(0, 0, textView.frame.size.width, 700);
				
				[textView setFrame:keyboardFrame];
			}
			
			[self.view bringSubviewToFront:textView];
		}
		else {
			// iPhone
			if ((self.interfaceOrientation == UIDeviceOrientationLandscapeLeft)
				|| (self.interfaceOrientation == UIDeviceOrientationLandscapeRight)) {
				// Landscape
				keyboardFrame = CGRectMake (0, 0, 480, 130);
			}
			else {
				// Portrait
				keyboardFrame = CGRectMake (0, 0, 320, 210);
			}
			
			[textView setFrame:keyboardFrame];
		}
	}
	else {
		// Normal mode
		
		// iPad
		if(DeviceIsPad() == YES) {
			if ((self.interfaceOrientation == UIDeviceOrientationLandscapeLeft)
				|| (self.interfaceOrientation == UIDeviceOrientationLandscapeRight)) {
				// Landscape
				keyboardFrame = CGRectMake(0, 180, textView.frame.size.width, normalTextFrame.size.height);
				
				[textView setFrame:keyboardFrame];
			}
			else {
				// Portrait
				keyboardFrame = CGRectMake(0, 180, textView.frame.size.width, normalTextFrame.size.height);
				
				[textView setFrame:keyboardFrame];
			}
			
			[self.view bringSubviewToFront:textView];
		}
		else {
			// iPhone
			if ((self.interfaceOrientation == UIDeviceOrientationLandscapeLeft)
				|| (self.interfaceOrientation == UIDeviceOrientationLandscapeRight)) {
				// Landscape
				keyboardFrame = CGRectMake(0, 165, 480, normalTextFrame.size.height);
			}
			else {
				// Portrait
				keyboardFrame = CGRectMake(0, 165, 320, normalTextFrame.size.height);
			}
			
			[textView setFrame:keyboardFrame];
		}
	}
	
	[UIView commitAnimations];
}

- (void)deviceDidRotate:(NSNotification *)notification {
	// If we're editing, adjust the textview
	if(self.isEditing) {
		[self positionTextView:nil];
	}
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    self.hasChanges = YES;
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    self.hasChanges = YES;
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    self.currentEditingTextField = nil;
    [textField resignFirstResponder];
    return YES;
}

- (void)insertMediaAbove:(NSNotification *)notification {
	Media *media = (Media *)[notification object];
	NSString *prefix = @"<br/><br/>";
	
	if(textView.text == nil)
		textView.text = @"";
	else if([textView.text isEqualToString:kTextViewPlaceholder]) {
		textViewPlaceHolderField.hidden = YES;
        textView.textColor = [UIColor blackColor];
		textView.text = @"";
		prefix = @"";
	}
	
	NSMutableString *content = [[[NSMutableString alloc] initWithString:media.html] autorelease];
	NSRange imgHTML = [textView.text rangeOfString:content];
	if (imgHTML.location == NSNotFound) {
		[content appendString:[NSString stringWithFormat:@"%@%@", prefix, textView.text]];
		textView.text = content;
		self.hasChanges = YES;
	}
}

- (void)insertMediaBelow:(NSNotification *)notification {
	Media *media = (Media *)[notification object];
	NSString *prefix = @"<br/><br/>";
	
	if(textView.text == nil)
		textView.text = @"";
	else if([textView.text isEqualToString:kTextViewPlaceholder]) {
		textViewPlaceHolderField.hidden = YES;
        textView.textColor = [UIColor blackColor];
		textView.text = @"";
		prefix = @"";
	}
	
	NSMutableString *content = [[[NSMutableString alloc] initWithString:textView.text] autorelease];
	NSRange imgHTML = [content rangeOfString:media.html];
	if (imgHTML.location == NSNotFound) {
		[content appendString:[NSString stringWithFormat:@"%@%@", prefix, media.html]];
		textView.text = content;
		self.hasChanges = YES;
	}
}

- (void)removeMedia:(NSNotification *)notification {
	Media *media = (Media *)[notification object];
	textView.text = [textView.text stringByReplacingOccurrencesOfString:media.html withString:@""];
}

- (void)readBookmarksFile {
    bookMarksArray = [[NSMutableArray alloc] init];
    //NSDictionary *bookMarksDict=[NSMutableDictionary dictionaryWithContentsOfFile:@"/Users/sridharrao/Library/Safari/Bookmarks.plist"];
    NSDictionary *bookMarksDict = [NSMutableDictionary dictionaryWithContentsOfFile:@"/Users/sridharrao/Library/Application%20Support/iPhone%20Simulator/User/Library/Safari/Bookmarks.plist"];
    NSArray *childrenArray = [bookMarksDict valueForKey:@"Children"];
    bookMarksDict = [childrenArray objectAtIndex:0];
    int count = [childrenArray count];
    childrenArray = [bookMarksDict valueForKey:@"Children"];
	
    for (int i = 0; i < count; i++) {
        bookMarksDict = [childrenArray objectAtIndex:i];
		
        if ([[bookMarksDict valueForKey:@"WebBookmarkType"] isEqualToString:@"WebBookmarkTypeLeaf"]) {
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            [dict setValue:[[bookMarksDict valueForKey:@"URIDictionary"] valueForKey:@"title"] forKey:@"title"];
            [dict setValue:[bookMarksDict valueForKey:@"URLString"] forKey:@"url"];
            [bookMarksArray addObject:dict];
            [dict release];
        }
    }
}

#pragma mark  -
#pragma mark Table Data Source Methods (for Custom Fields TableView only)

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
	
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:CellIdentifier] autorelease];
		
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 200, 25)];
        label.textAlignment = UITextAlignmentLeft;
        //label.tag = kLabelTag;
        label.font = [UIFont systemFontOfSize:16];
        label.textColor = [UIColor grayColor];
        [cell.contentView addSubview:label];
        [label release];
    }
	
    NSUInteger row = [indexPath row];
	
    //UILabel *label = (UILabel *)[cell viewWithTag:kLabelTag];
	
    if (row == 0) {
        //label.text = @"Edit Custom Fields";
        //label.font = [UIFont systemFontOfSize:16 ];
    } else {
        //do nothing because we've only got one cell right now
    }
	cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    cell.userInteractionEnabled = YES;
    return cell;
}

//- (UITableViewCellAccessoryType)tableView:(UITableView *)tableView accessoryTypeForRowWithIndexPath:(NSIndexPath *)indexPath {
//    return UITableViewCellAccessoryDisclosureIndicator;
//}

#pragma mark -
#pragma mark Table delegate
- (NSIndexPath *)tableView:(UITableView *)tableView
  willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    return nil;
}

#pragma mark -
#pragma mark Custom Fields methods

- (BOOL)checkCustomFieldsMinusMetadata {
    BlogDataManager *dm = [BlogDataManager sharedDataManager];
    NSMutableArray *tempCustomFieldsArray = [dm.currentPost valueForKey:@"custom_fields"];
	
    //if there is anything (>=1) in the array, start proceessing, otherwise return NO
    if (tempCustomFieldsArray.count >= 1) {
        //strip out any underscore-containing NSDicts inside the array, as this is metadata we don't need
        int dictsCount = [tempCustomFieldsArray count];
		
        for (int i = 0; i < dictsCount; i++) {
            NSString *tempKey = [[tempCustomFieldsArray objectAtIndex:i] objectForKey:@"key"];
			
            //if tempKey contains an underscore, remove that object (NSDict with metadata) from the array and move on
            if(([tempKey rangeOfString:@"_"].location != NSNotFound) && ([tempKey rangeOfString:@"geo_"].location == NSNotFound)) {
                [tempCustomFieldsArray removeObjectAtIndex:i];
                //if I remove one, the count goes down and we stop too soon unless we subtract one from i
                //and re-set dictsCount.  Doing this keeps us in sync with the actual array.count
                i--;
                dictsCount = [tempCustomFieldsArray count];
            }
        }
		
        //if the count of everything minus the metedata is one or greater, there is at least one custom field on this post, so return YES
        if (dictsCount >= 1) {
            return YES;
        } else {
            return NO;
        }
    } else {
        return NO;
    }
}

#pragma mark -
#pragma mark Location methods

- (BOOL)isPostGeotagged {
	if([self getPostLocation] != nil) {
		self.hasChanges = YES;
		return YES;
	}
	else
		return NO;
}

- (IBAction)showLocationMapView:(id)sender {
	WordPressAppDelegate *delegate = (WordPressAppDelegate *)[[UIApplication sharedApplication] delegate];
	PostLocationViewController *locationView = [[PostLocationViewController alloc] initWithNibName:@"PostLocationViewController" bundle:nil];
	[delegate.navigationController presentModalViewController:locationView animated:YES];
	[locationView release];
}

- (CLLocation *)getPostLocation {
	CLLocation *result = nil;
	double latitude = 0.0;
	double longitude = 0.0;
    NSArray *customFieldsArray = [[[BlogDataManager sharedDataManager] currentPost] valueForKey:@"custom_fields"];
	
	// Loop through the post's custom fields
	for(NSDictionary *dict in customFieldsArray)
	{
		// Latitude
		if([[dict objectForKey:@"key"] isEqualToString:@"geo_latitude"])
			latitude = [[dict objectForKey:@"value"] doubleValue];
		
		// Longitude
		if([[dict objectForKey:@"key"] isEqualToString:@"geo_longitude"])
			longitude = [[dict objectForKey:@"value"] doubleValue];
		
		// If we have both lat and long, we have a geotag
		if((latitude != 0.0) && (longitude != 0.0))
		{
			result = [[[CLLocation alloc] initWithLatitude:latitude longitude:longitude] autorelease];
			break;
		}
		else
			result = nil;
	}
	
	return result;
}

#pragma mark -
#pragma mark Keyboard management 

- (void)keyboardWillShow:(NSNotification *)notification {
	isShowingKeyboard = YES;
}

- (void)keyboardWillHide:(NSNotification *)notification {
	isShowingKeyboard = NO;
}

#pragma mark -
#pragma mark UIPickerView delegate

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)thePickerView {	
	return 1;
}

- (NSInteger)pickerView:(UIPickerView *)thePickerView numberOfRowsInComponent:(NSInteger)component {
	return [statuses count];
}

- (NSString *)pickerView:(UIPickerView *)thePickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
	return [statuses objectAtIndex:row];
}

- (void)pickerView:(UIPickerView *)thePickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
	self.statusTextField.text = [statuses objectAtIndex:row];
}

#pragma mark -
#pragma mark UIPopoverController delegate

- (BOOL)popoverControllerShouldDismissPopover:(UIPopoverController *)popoverController {
    if ((popoverController.contentViewController) && ([popoverController.contentViewController class] == [UINavigationController class])) {
        UINavigationController *nav = (UINavigationController *)popoverController.contentViewController;
        if ([nav.viewControllers count] == 2) {
            WPSegmentedSelectionTableViewController *selController = [nav.viewControllers objectAtIndex:0];
            [selController popViewControllerAnimated:YES];
        }
    }
    return YES;
}

#pragma mark -
#pragma mark Memory management

- (void)didReceiveMemoryWarning {
    WPLog(@"%@ %@", self, NSStringFromSelector(_cmd));
    [super didReceiveMemoryWarning];
}

#pragma mark -
#pragma mark Dealloc

- (void)dealloc {
//	[statuses release];
    [writeButton release];
    [settingsButton release];
	[textView release];
	[contentView release];
	[subView release];
	[textViewContentView release];
	[statusTextField release];
	[categoriesTextField release];
	[titleTextField release];
	[tagsTextField release];
	[textViewPlaceHolderField release];
	[tagsLabel release];
	[statusLabel release];
	[categoriesLabel release];
	[titleLabel release];
	[customFieldsEditButton release];
	[locationButton release];
	[locationSpinner release];
	[newCategoryBarButtonItem release];
    [infoText release];
    [urlField release];
    [bookMarksArray release];
    [segmentedTableViewController release];
    [super dealloc];
}


@end
