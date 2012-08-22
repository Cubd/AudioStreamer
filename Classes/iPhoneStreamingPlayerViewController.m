//
//  iPhoneStreamingPlayerViewController.m
//  iPhoneStreamingPlayer
//
//  Created by Matt Gallagher on 28/10/08.
//  Copyright Matt Gallagher 2008. All rights reserved.
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//

#import "iPhoneStreamingPlayerAppDelegate.h"
#import "iPhoneStreamingPlayerViewController.h"
#import "AudioStreamer.h"
#import "LevelMeterView.h"
#import <QuartzCore/CoreAnimation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CFNetwork/CFNetwork.h>


@interface iPhoneStreamingPlayerViewController()

@property (strong, nonatomic) IBOutlet UILabel *metadataArtistLabel;
@property (strong, nonatomic) IBOutlet UILabel *metadataTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *metadataAlbumLabel;
@property (strong, nonatomic) IBOutlet UITextField *downloadSourceField;
@property (strong, nonatomic) IBOutlet UIButton *button;
@property (strong, nonatomic) IBOutlet UILabel *positionLabel;
@property (strong, nonatomic) IBOutlet UISlider *progressSlider;
@property (strong, nonatomic) IBOutlet UIView *volumeSlider;
@property (strong, nonatomic) NSString *currentImageName;
@property (strong, nonatomic) NSString *currentArtist;
@property (strong, nonatomic) NSString *currentTitle;
@property (strong, nonatomic) NSTimer *progressUpdateTimer;
@property (strong, nonatomic) NSTimer *levelMeterUpdateTimer;
@property (strong, nonatomic) AudioStreamer *streamer;
@property (strong, nonatomic) LevelMeterView *levelMeterView;
@property (assign, nonatomic) BOOL uiIsVisible;

- (void)setButtonImageNamed:(NSString *)imageName;
- (void)destroyStreamer;
- (void)createStreamer;
- (IBAction)buttonPressed:(id)sender;
- (IBAction)sliderMoved:(UISlider *)aSlider;
- (void)spinButton;
- (void)forceUIUpdate;
- (void)createTimers:(BOOL)create;
- (void)updateProgress:(NSTimer *)updatedTimer;
- (void)playbackStateChanged:(NSNotification *)aNotification;
- (void)applicationStateDidChange:(NSNotification *)notification;

@end


@implementation iPhoneStreamingPlayerViewController

//
// setButtonImageNamed:
//
// Used to change the image on the playbutton. This method exists for
// the purpose of inter-thread invocation because
// the observeValueForKeyPath:ofObject:change:context: method is invoked
// from secondary threads and UI updates are only permitted on the main thread.
//
// Parameters:
//    imageNamed - the name of the image to set on the play button.
//
- (void)setButtonImageNamed:(NSString *)imageName
{
	if (!imageName)
	{
		imageName = @"playButton";
	}
	self.currentImageName = imageName;
	
	UIImage *image = [UIImage imageNamed:imageName];
	
	[self.button.layer removeAllAnimations];
	[self.button setImage:image forState:UIControlStateNormal];
		
	if ([imageName isEqual:@"loadingbutton.png"])
	{
		[self spinButton];
	}
}

//
// destroyStreamer
//
// Removes the streamer, the UI update timer and the change notification
//
- (void)destroyStreamer
{
    if (_streamer)
	{
        [[NSNotificationCenter defaultCenter] removeObserver:self name:ASStatusChangedNotification object:_streamer];
#ifdef SHOUTCAST_METADATA
        [[NSNotificationCenter defaultCenter] removeObserver:self name:ASUpdateMetadataNotification object:_streamer];
#endif
        [self createTimers:NO];
		[_streamer stop];
		_streamer = nil;
	}
}



//
// createStreamer
//
// Creates or recreates the AudioStreamer object.
//
- (void)createStreamer
{
    if (_streamer)
    {
        return;
    }
    	
	NSString *escapedValue = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(nil, (__bridge CFStringRef)self.downloadSourceField.text, NULL, NULL, kCFStringEncodingUTF8));

	NSURL *url = [NSURL URLWithString:escapedValue];
	_streamer = [[AudioStreamer alloc] initWithURL:url];
	
    [self createTimers:YES];
    
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackStateChanged:) name:ASStatusChangedNotification object:_streamer];
#ifdef SHOUTCAST_METADATA
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(metadataChanged:) name:ASUpdateMetadataNotification object:_streamer];
#endif
}

//
// viewDidLoad
//
// Creates the volume slider, sets the default path for the local file and
// creates the streamer immediately if we already have a file at the local
// location.
//
- (void)viewDidLoad
{
	[super viewDidLoad];
	
	MPVolumeView *volumeView = [[MPVolumeView alloc] initWithFrame:self.volumeSlider.bounds];
	[self.volumeSlider addSubview:volumeView];
	[volumeView sizeToFit];
	
	[self setButtonImageNamed:@"playbutton.png"];
    
    self.levelMeterView = [[LevelMeterView alloc] initWithFrame:CGRectMake(10.0f, 360.0f, 300.0f, 60.0f)];
	[self.view addSubview:self.levelMeterView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationStateDidChange:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationStateDidChange:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(presentAlertWithTitle:) name:ASPresentAlertWithTitleNotification object:nil];

}



//
// spinButton
//
// Shows the spin button when the audio is loading. This is largely irrelevant
// now that the audio is loaded from a local file.
//
- (void)spinButton
{
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	CGRect frame = [self.button frame];
	self.button.layer.anchorPoint = CGPointMake(0.5f, 0.5f);
	self.button.layer.position = CGPointMake(frame.origin.x + 0.5f * frame.size.width, frame.origin.y + 0.5f * frame.size.height);
	[CATransaction commit];

	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanFalse forKey:kCATransactionDisableActions];
	[CATransaction setValue:[NSNumber numberWithFloat:2.0f] forKey:kCATransactionAnimationDuration];

	CABasicAnimation *animation;
	animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
	animation.fromValue = [NSNumber numberWithFloat:0.0f];
	animation.toValue = [NSNumber numberWithFloat:2.0f * M_PI];
	animation.timingFunction = [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionLinear];
	animation.delegate = self;
	[self.button.layer addAnimation:animation forKey:@"rotationAnimation"];

	[CATransaction commit];
}

//
// animationDidStop:finished:
//
// Restarts the spin animation on the button when it ends. Again, this is
// largely irrelevant now that the audio is loaded from a local file.
//
// Parameters:
//    theAnimation - the animation that rotated the button.
//    finished - is the animation finised?
//
- (void)animationDidStop:(CAAnimation *)theAnimation finished:(BOOL)finished
{
	if (finished)
	{
		[self spinButton];
	}
}

//
// buttonPressed:
//
// Handles the play/stop button. Creates, observes and starts the
// audio streamer when it is a play button. Stops the audio streamer when
// it isn't.
//
// Parameters:
//    sender - normally, the play/stop button.
//
- (IBAction)buttonPressed:(id)sender
{
	if ([self.currentImageName isEqual:@"playbutton.png"])
	{
		[self.downloadSourceField resignFirstResponder];
		
		[self createStreamer];
		[self setButtonImageNamed:@"loadingbutton.png"];
		[self.streamer start];
	}
	else
	{
		[self.streamer stop];
	}
}

//
// sliderMoved:
//
// Invoked when the user moves the slider
//
// Parameters:
//    aSlider - the slider (assumed to be the progress slider)
//
- (IBAction)sliderMoved:(UISlider *)aSlider
{
	if (self.streamer.duration)
	{
		double newSeekTime = (aSlider.value / 100.0) * self.streamer.duration;
		[self.streamer seekToTime:newSeekTime];
	}
}

//
// playbackStateChanged:
//
// Invoked when the AudioStreamer
// reports that its playback status has changed.
//
- (void)playbackStateChanged:(NSNotification *)aNotification
{
	if ([self.streamer isWaiting])
	{
        if (self.uiIsVisible)
        {
            [self.levelMeterView updateMeterWithLeftValue:0.0f rightValue:0.0f];
            [self.streamer setMeteringEnabled:NO];
            [self setButtonImageNamed:@"loadingbutton.png"];
        }
	}
	else if ([self.streamer isPlaying])
	{
        if (self.uiIsVisible)
        {
            [self.streamer setMeteringEnabled:YES];
            [self setButtonImageNamed:@"stopbutton.png"];
        }
	}
    else if ([self.streamer isPaused])
    {
        if (self.uiIsVisible)
        {
            [self.levelMeterView updateMeterWithLeftValue:0.0f rightValue:0.0f];
            [self.streamer setMeteringEnabled:NO];
            [self setButtonImageNamed:@"pausebutton.png"];
        }
    }
	else if ([self.streamer isIdle])
	{
        if (self.uiIsVisible)
        {
            [self.levelMeterView updateMeterWithLeftValue:0.0f rightValue:0.0f];
            [self setButtonImageNamed:@"playbutton.png"];
        }
        [self destroyStreamer];
    }
}



//
// updateProgress:
//
// Invoked when the AudioStreamer
// reports that its playback progress has changed.
//
- (void)updateProgress:(NSTimer *)updatedTimer
{
	if (self.streamer.bitRate != 0.0)
	{
		double progress = self.streamer.progress;
		double duration = self.streamer.duration;
        
		if (duration > 0)
		{
			[self.positionLabel setText:[NSString stringWithFormat:@"Time Played: %.1f/%.1f seconds", progress, duration]];
			[self.progressSlider setEnabled:YES];
			[self.progressSlider setValue:100 * progress / duration];
		}
		else
		{
			[self.progressSlider setEnabled:NO];
		}
	}
	else
	{
		self.positionLabel.text = @"Time Played:";
	}
}

//
// textFieldShouldReturn:
//
// Dismiss the text field when done is pressed
//
// Parameters:
//    sender - the text field
//
// returns YES
//
- (BOOL)textFieldShouldReturn:(UITextField *)sender
{
	[sender resignFirstResponder];
	[self createStreamer];
	return YES;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self createTimers:NO];
	[self destroyStreamer];
}

#ifdef SHOUTCAST_METADATA
/** Example metadata
 *
 StreamTitle='Kim Sozzi / Amuka / Livvi Franc - Secret Love / It's Over / Automatik',
 StreamUrl='&artist=Kim%20Sozzi%20%2F%20Amuka%20%2F%20Livvi%20Franc&title=Secret%20Love%20%2F%20It%27s%20Over%20%2F%20Automatik&album=&duration=1133453&songtype=S&overlay=no&buycd=&website=&picture=',
 
 Format is generally "Artist hypen Title" although servers may deliver only one. This code assumes 1 field is artist.
 */
- (void)metadataChanged:(NSNotification *)aNotification
{
	NSString *streamArtist;
	NSString *streamTitle;
	NSString *streamAlbum;
    //NSLog(@"Raw meta data = %@", [[aNotification userInfo] objectForKey:@"metadata"]);
    
	NSArray *metaParts = [[[aNotification userInfo] objectForKey:@"metadata"] componentsSeparatedByString:@";"];
	NSString *item;
	NSMutableDictionary *hash = [[NSMutableDictionary alloc] init];
	for (item in metaParts)
    {
		// split the key/value pair
		NSArray *pair = [item componentsSeparatedByString:@"="];
		// don't bother with bad metadata
		if ([pair count] == 2)
			[hash setObject:[pair objectAtIndex:1] forKey:[pair objectAtIndex:0]];
	}
    
	// do something with the StreamTitle
	NSString *streamString = [[hash objectForKey:@"StreamTitle"] stringByReplacingOccurrencesOfString:@"'" withString:@""];
    
	NSArray *streamParts = [streamString componentsSeparatedByString:@" - "];
	if ([streamParts count] > 0)
    {
		streamArtist = [streamParts objectAtIndex:0];
	}
    else
    {
		streamArtist = @"";
	}
	// this looks odd but not every server will have all artist hyphen title
	if ([streamParts count] >= 2)
    {
		streamTitle = [streamParts objectAtIndex:1];
		if ([streamParts count] >= 3)
        {
			streamAlbum = [streamParts objectAtIndex:2];
		}
        else
        {
			streamAlbum = @"N/A";
		}
	}
    else
    {
		streamTitle = @"";
		streamAlbum = @"";
	}
	NSLog(@"%@ by %@ from %@", streamTitle, streamArtist, streamAlbum);
    
	// only update the UI if in foreground
	if (self.uiIsVisible)
    {
		self.metadataArtistLabel.text = streamArtist;
		self.metadataTitleLabel.text = streamTitle;
		self.metadataAlbumLabel.text = streamAlbum;
	}
	self.currentArtist = streamArtist;
	self.currentTitle = streamTitle;
}
#endif

//
// updateLevelMeters:
//

- (void)updateLevelMeters:(NSTimer *)timer
{
    if ([self.streamer isMeteringEnabled] && self.uiIsVisible)
    {
        [self.levelMeterView updateMeterWithLeftValue:[self.streamer averagePowerForChannel:0] rightValue:[self.streamer averagePowerForChannel:([self.streamer numberOfChannels] > 1 ? 1 : 0)]];
    }
}



//
// forceUIUpdate
//
// When foregrounded force UI update since we didn't update in the background
//
-(void)forceUIUpdate
{
	if (self.currentArtist)
    {
        self.metadataArtistLabel.text = self.currentArtist;
    }
	if (self.currentTitle)
    {
        self.metadataTitleLabel.text = self.currentTitle;
    }
    
	if (!self.streamer)
    {
		[self.levelMeterView updateMeterWithLeftValue:0.0
									  rightValue:0.0];
		[self setButtonImageNamed:@"playbutton.png"];
	}
	else
    {
        [self playbackStateChanged:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
    
	UIApplication *application = [UIApplication sharedApplication];
	if([application respondsToSelector:@selector(beginReceivingRemoteControlEvents)])
    {
        [application beginReceivingRemoteControlEvents];
    }
	[self becomeFirstResponder]; // this enables listening for events
	// update the UI in case we were in the background
    [self forceUIUpdate];
}

- (BOOL)canBecomeFirstResponder
{
	return YES;
}

//
// createTimers
//
// Creates or destoys the timers
//
-(void)createTimers:(BOOL)create
{
	if (create)
    {
		if (self.streamer)
        {
            [self createTimers:NO];
            self.progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateProgress:) userInfo:nil repeats:YES];
            self.levelMeterUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(updateLevelMeters:) userInfo:nil repeats:YES];
		}
	}
	else
    {
		if (self.progressUpdateTimer)
		{
			[self.progressUpdateTimer invalidate];
			self.progressUpdateTimer = nil;
		}
		if (self.levelMeterUpdateTimer)
        {
			[self.levelMeterUpdateTimer invalidate];
			self.levelMeterUpdateTimer = nil;
		}
	}
}

#pragma mark Remote Control Events
/* The iPod controls will send these events when the app is in the background */
- (void)remoteControlReceivedWithEvent:(UIEvent *)event
{
	switch (event.subtype)
    {
		case UIEventSubtypeRemoteControlTogglePlayPause:
			[self.streamer pause];
			break;
		case UIEventSubtypeRemoteControlPlay:
			[self.streamer start];
			break;
		case UIEventSubtypeRemoteControlPause:
			[self.streamer pause];
			break;
		case UIEventSubtypeRemoteControlStop:
			[self.streamer stop];
			break;
		default:
			break;
	}
}

- (void)applicationStateDidChange:(NSNotification *)notification
{
    if ([notification.name isEqualToString:UIApplicationDidBecomeActiveNotification])
    {
        self.uiIsVisible = YES;
    }
    else if ([notification.name isEqualToString:UIApplicationDidEnterBackgroundNotification])
    {
        self.uiIsVisible = NO;
    }
}

- (void)presentAlertWithTitle:(NSNotification *)notification
{
    NSString *title = [[notification userInfo] objectForKey:@"title"];
    NSString *message = [[notification userInfo] objectForKey:@"message"];
    
    dispatch_queue_t main_queue = dispatch_get_main_queue();
    
    dispatch_async(main_queue, ^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles: nil];
        [alert show];
    });
}

@end
