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

@property (assign, nonatomic) BOOL uiIsVisible;

- (void)playbackStateChanged:(NSNotification *)aNotification;
- (void)destroyStreamer;
- (void)createStreamer;
- (void)setButtonImageNamed:(NSString *)imageName;
- (void)applicationStateDidChange:(NSNotification *)notification;

@end


@implementation iPhoneStreamingPlayerViewController

@synthesize currentArtist, currentTitle;
@synthesize uiIsVisible;

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
	currentImageName = imageName;
	
	UIImage *image = [UIImage imageNamed:imageName];
	
	[button.layer removeAllAnimations];
	[button setImage:image forState:UIControlStateNormal];
		
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
    if (streamer)
	{
        [[NSNotificationCenter defaultCenter] removeObserver:self name:ASStatusChangedNotification object:streamer];
#ifdef SHOUTCAST_METADATA
        [[NSNotificationCenter defaultCenter] removeObserver:self name:ASUpdateMetadataNotification object:streamer];
#endif
        [self createTimers:NO];
		[streamer stop];
		streamer = nil;
	}
}



//
// createStreamer
//
// Creates or recreates the AudioStreamer object.
//
- (void)createStreamer
{
    if (streamer)
    {
        return;
    }
    	
	NSString *escapedValue = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(nil, (__bridge CFStringRef)downloadSourceField.text, NULL, NULL, kCFStringEncodingUTF8));

	NSURL *url = [NSURL URLWithString:escapedValue];
	streamer = [[AudioStreamer alloc] initWithURL:url];
	
    [self createTimers:YES];
    
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackStateChanged:) name:ASStatusChangedNotification object:streamer];
#ifdef SHOUTCAST_METADATA
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(metadataChanged:) name:ASUpdateMetadataNotification object:streamer];
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
	
	MPVolumeView *volumeView = [[MPVolumeView alloc] initWithFrame:volumeSlider.bounds];
	[volumeSlider addSubview:volumeView];
	[volumeView sizeToFit];
	
	[self setButtonImageNamed:@"playbutton.png"];
    
    levelMeterView = [[LevelMeterView alloc] initWithFrame:CGRectMake(10.0f, 310.0f, 300.0f, 60.0f)];
	[self.view addSubview:levelMeterView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationStateDidChange:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationStateDidChange:) name:UIApplicationDidEnterBackgroundNotification object:nil];
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
	CGRect frame = [button frame];
	button.layer.anchorPoint = CGPointMake(0.5f, 0.5f);
	button.layer.position = CGPointMake(frame.origin.x + 0.5f * frame.size.width, frame.origin.y + 0.5f * frame.size.height);
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
	[button.layer addAnimation:animation forKey:@"rotationAnimation"];

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
	if ([currentImageName isEqual:@"playbutton.png"])
	{
		[downloadSourceField resignFirstResponder];
		
		[self createStreamer];
		[self setButtonImageNamed:@"loadingbutton.png"];
		[streamer start];
	}
	else
	{
		[streamer stop];
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
	if (streamer.duration)
	{
		double newSeekTime = (aSlider.value / 100.0) * streamer.duration;
		[streamer seekToTime:newSeekTime];
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
	if ([streamer isWaiting])
	{
        if (self.uiIsVisible)
        {
            [levelMeterView updateMeterWithLeftValue:0.0f rightValue:0.0f];
            [streamer setMeteringEnabled:NO];
            [self setButtonImageNamed:@"loadingbutton.png"];
        }
	}
	else if ([streamer isPlaying])
	{
        if (self.uiIsVisible)
        {
            [streamer setMeteringEnabled:YES];
            [self setButtonImageNamed:@"stopbutton.png"];
        }
	}
    else if ([streamer isPaused])
    {
        if (self.uiIsVisible)
        {
            [levelMeterView updateMeterWithLeftValue:0.0f rightValue:0.0f];
            [streamer setMeteringEnabled:NO];
            [self setButtonImageNamed:@"pausebutton.png"];
        }
    }
	else if ([streamer isIdle])
	{
        if (self.uiIsVisible)
        {
            [levelMeterView updateMeterWithLeftValue:0.0f rightValue:0.0f];
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
	if (streamer.bitRate != 0.0)
	{
		double progress = streamer.progress;
		double duration = streamer.duration;
        
		if (duration > 0)
		{
			[positionLabel setText:[NSString stringWithFormat:@"Time Played: %.1f/%.1f seconds", progress, duration]];
			[progressSlider setEnabled:YES];
			[progressSlider setValue:100 * progress / duration];
		}
		else
		{
			[progressSlider setEnabled:NO];
		}
	}
	else
	{
		positionLabel.text = @"Time Played:";
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
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    
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
		metadataArtist.text = streamArtist;
		metadataTitle.text = streamTitle;
		metadataAlbum.text = streamAlbum;
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
    if ([streamer isMeteringEnabled] && self.uiIsVisible)
    {
        [levelMeterView updateMeterWithLeftValue:[streamer averagePowerForChannel:0] rightValue:[streamer averagePowerForChannel:([streamer numberOfChannels] > 1 ? 1 : 0)]];
    }
}



//
// forceUIUpdate
//
// When foregrounded force UI update since we didn't update in the background
//
-(void)forceUIUpdate
{
	if (currentArtist)
    {
        metadataArtist.text = currentArtist;
    }
	if (currentTitle)
    {
        metadataTitle.text = currentTitle;
    }
    
	if (!streamer)
    {
		[levelMeterView updateMeterWithLeftValue:0.0
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
		if (streamer)
        {
            [self createTimers:NO];
            progressUpdateTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateProgress:) userInfo:nil repeats:YES];
            levelMeterUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(updateLevelMeters:) userInfo:nil repeats:YES];
		}
	}
	else
    {
		if (progressUpdateTimer)
		{
			[progressUpdateTimer invalidate];
			progressUpdateTimer = nil;
		}
		if (levelMeterUpdateTimer)
        {
			[levelMeterUpdateTimer invalidate];
			levelMeterUpdateTimer = nil;
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
			[streamer pause];
			break;
		case UIEventSubtypeRemoteControlPlay:
			[streamer start];
			break;
		case UIEventSubtypeRemoteControlPause:
			[streamer pause];
			break;
		case UIEventSubtypeRemoteControlStop:
			[streamer stop];
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

@end
