//
//  JSTalk.m
//  jstalk
//
//  Created by August Mueller on 1/15/09.
//  Copyright 2009 Flying Meat Inc. All rights reserved.
//

#import "JSTalk.h"
#import "JSTListener.h"
#import "JSTPreprocessor.h"
#import <ScriptingBridge/ScriptingBridge.h>
#import "MochaRuntime.h"
#import "MOMethod.h"
#import "MOBridgeSupportController.h"

extern int *_NSGetArgc(void);
extern char ***_NSGetArgv(void);

static BOOL JSTalkShouldLoadJSTPlugins = YES;
static NSMutableArray *JSTalkPluginList;

@interface JSTalk (Private)
- (void) print:(NSString*)s;
@end


@implementation JSTalk
@synthesize printController=_printController;
@synthesize errorController=_errorController;
@synthesize env=_env;
@synthesize shouldPreprocess=_shouldPreprocess;

+ (void)listen {
    [JSTListener listen];
}

+ (void)setShouldLoadExtras:(BOOL)b {
    JSTalkShouldLoadJSTPlugins = b;
}

+ (void)setShouldLoadJSTPlugins:(BOOL)b {
    JSTalkShouldLoadJSTPlugins = b;
}

- (id)init {
	self = [super init];
	if ((self != nil)) {
        _mochaRuntime = [[Mocha alloc] init];
        
        self.env = [NSMutableDictionary dictionary];
        _shouldPreprocess = YES;
        
        
        [_mochaRuntime setValue:[MOMethod methodWithTarget:self selector:@selector(print:)] forKey:@"print"];
	}
    
	return self;
}


- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    
    if ([_mochaRuntime context]) {
        JSGarbageCollect([_mochaRuntime context]);
    }
    
    
    [_mochaRuntime release];
    _mochaRuntime = nil;
    
    [_env release];
    _env = nil;
    
    [super dealloc];
}


- (Mocha*)mochaRuntime {
    return _mochaRuntime;
}

+ (void)loadExtraAtPath:(NSString*)fullPath {
    
    Class pluginClass;
    
    @try {
        
        NSBundle *pluginBundle = [NSBundle bundleWithPath:fullPath];
        if (!pluginBundle) {
            return;
        }
        
        NSString *principalClassName = [[pluginBundle infoDictionary] objectForKey:@"NSPrincipalClass"];
        
        if (principalClassName && NSClassFromString(principalClassName)) {
            NSLog(@"The class %@ is already loaded, skipping the load of %@", principalClassName, fullPath);
            return;
        }
        
        [principalClassName class]; // force loading of it.
        
        NSError *err = nil;
        [pluginBundle loadAndReturnError:&err];
        
        if (err) {
            NSLog(@"Error loading plugin at %@", fullPath);
            NSLog(@"%@", err);
        }
        else if ((pluginClass = [pluginBundle principalClass])) {
            
            // do we want to actually do anything with em' at this point?
            
            NSString *bridgeSupportName = [[pluginBundle infoDictionary] objectForKey:@"BridgeSuportFileName"];
            
            if (bridgeSupportName) {
                NSString *bridgeSupportPath = [pluginBundle pathForResource:bridgeSupportName ofType:nil];
                
                NSError *outErr = nil;
                if (![[MOBridgeSupportController sharedController] loadBridgeSupportAtURL:[NSURL fileURLWithPath:bridgeSupportPath] error:&outErr]) {
                    NSLog(@"Could not load bridge support file at %@", bridgeSupportPath);
                }
            }
        }
        else {
            //debug(@"Could not load the principal class of %@", fullPath);
            //debug(@"infoDictionary: %@", [pluginBundle infoDictionary]);
        }
        
    }
    @catch (NSException * e) {
        NSLog(@"EXCEPTION: %@: %@", [e name], e);
    }
    
}

+ (void)resetPlugins {
    [JSTalkPluginList release];
    JSTalkPluginList = nil;
}

+ (void)loadPlugins {
    
    // install plugins that were passed via the command line
    int i = 0;
    char **argv = *_NSGetArgv();
    for (i = 0; argv[i] != NULL; ++i) {
        
        NSString *a = [NSString stringWithUTF8String:argv[i]];
        
        if ([@"-jstplugin" isEqualToString:a]) {
            i++;
            NSLog(@"Loading plugin at: [%@]", [NSString stringWithUTF8String:argv[i]]);
            [self loadExtraAtPath:[NSString stringWithUTF8String:argv[i]]];
        }
    }
    
    JSTalkPluginList = [[NSMutableArray array] retain];
    
    NSString *appSupport = @"Library/Application Support/JSTalk/Plug-ins";
    NSString *appPath    = [[NSBundle mainBundle] builtInPlugInsPath];
    NSString *sysPath    = [@"/" stringByAppendingPathComponent:appSupport];
    NSString *userPath   = [NSHomeDirectory() stringByAppendingPathComponent:appSupport];
    
    
    // only make the JSTalk dir if we're JSTalkEditor.
    // or don't ever make it, since you'll get rejected from the App Store. *sigh*
    /*
    if (![[NSFileManager defaultManager] fileExistsAtPath:userPath]) {
        
        NSString *mainBundleId = [[NSBundle mainBundle] bundleIdentifier];
        
        if ([@"org.jstalk.JSTalkEditor" isEqualToString:mainBundleId]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:userPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    */
    
    for (NSString *folder in [NSArray arrayWithObjects:appPath, sysPath, userPath, nil]) {
        
        for (NSString *bundle in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:nil]) {
            
            if (!([bundle hasSuffix:@".jstplugin"])) {
                continue;
            }
            
            [self loadExtraAtPath:[folder stringByAppendingPathComponent:bundle]];
        }
    }
    
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"org.jstalk.JSTalkEditor"]) {
        
        NSURL *jst = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"org.jstalk.JSTalkEditor"];
        
        if (jst) {
            
            NSURL *folder = [[jst URLByAppendingPathComponent:@"Contents"] URLByAppendingPathComponent:@"PlugIns"];
            
            for (NSString *bundle in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[folder path] error:nil]) {
                
                if (!([bundle hasSuffix:@".jstplugin"])) {
                    continue;
                }
                
                [self loadExtraAtPath:[[folder path] stringByAppendingPathComponent:bundle]];
            }
        }
    }
}

NSString *currentJSTalkThreadIdentifier = @"org.jstalk.currentJSTalkHack";

+ (JSTalk*)currentJSTalk {
    return [[[NSThread currentThread] threadDictionary] objectForKey:currentJSTalkThreadIdentifier];
}

- (void)pushAsCurrentJSTalk {
    [[[NSThread currentThread] threadDictionary] setObject:self forKey:currentJSTalkThreadIdentifier];
}

- (void)popAsCurrentJSTalk {
    [[[NSThread currentThread] threadDictionary] removeObjectForKey:currentJSTalkThreadIdentifier];
}

- (void)pushObject:(id)obj withName:(NSString*)name  {
    [_mochaRuntime setValue:obj forKey:name];
}

- (void)deleteObjectWithName:(NSString*)name {
    
    /*
    JSContextRef ctx                = [_jsController ctx];
    JSStringRef jsName              = JSStringCreateWithUTF8CString([name UTF8String]);

    JSObjectDeleteProperty(ctx, JSContextGetGlobalObject(ctx), jsName, NULL);
    
    JSStringRelease(jsName);  
     */
}


- (id)executeString:(NSString*)str {
    
    if (!JSTalkPluginList && JSTalkShouldLoadJSTPlugins) {
        [JSTalk loadPlugins];
    }
    
    if (_shouldPreprocess) {
        str = [JSTPreprocessor preprocessCode:str];
    }
    
    [self pushObject:self withName:@"jstalk"];
    [self pushAsCurrentJSTalk];
    
    JSValueRef resultRef = nil;
    id resultObj = nil;
    
    @try {
        
        id result = [_mochaRuntime evalObjJSString:str];
        
        if (result) {
            [self print:[result description]];
        }
        
        
        
        /*
        [_jsController setUseAutoCall:NO];
        [_jsController setUseJSLint:NO];
        resultRef = [_jsController evalJSString:[NSString stringWithFormat:@"function print(s) { jstalk.print_(s); } var nil=null; %@", str]];
         */
    }
    @catch (NSException * e) {
        NSLog(@"Exception: %@", e);
        [self print:[e description]];
    }
    @finally {
        //
    }
    
    if (resultRef) {
        //[JSCocoaFFIArgument unboxJSValueRef:resultRef toObject:&resultObj inContext:[[self jsController] ctx]];
    }
    
    [self popAsCurrentJSTalk];
    
    //[self deleteObjectWithName:@"jstalk"];
    
    // this will free up the reference to ourself
    //if ([_jsController ctx]) {
    //    JSGarbageCollect([_jsController ctx]);
    //}
    
    return resultObj;
}

- (id)callFunctionNamed:(NSString*)name withArguments:(NSArray*)args {
    /*
    JSCocoaController *jsController = [self jsController];
    JSContextRef ctx                = [jsController ctx];
    
    JSValueRef exception            = nil;
    JSStringRef functionName        = JSStringCreateWithUTF8CString([name UTF8String]);
    JSValueRef functionValue        = JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), functionName, &exception);
    
    JSStringRelease(functionName);  
    
    JSValueRef returnValue = [jsController callJSFunction:functionValue withArguments:args];
    
    id returnObject;
    [JSCocoaFFIArgument unboxJSValueRef:returnValue toObject:&returnObject inContext:ctx];
    
    return returnObject;
     */
    return nil;
}

- (void)include:(NSString*)fileName {
    
    if (![fileName hasPrefix:@"/"] && [_env objectForKey:@"scriptURL"]) {
        NSString *parentDir = [[[_env objectForKey:@"scriptURL"] path] stringByDeletingLastPathComponent];
        fileName = [parentDir stringByAppendingPathComponent:fileName];
    }
    
    NSURL *scriptURL = [NSURL fileURLWithPath:fileName];
    NSError *err = nil;
    NSString *str = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:&err];
    
    if (!str) {
        NSLog(@"Could not open file '%@'", scriptURL);
        NSLog(@"Error: %@", err);
        return;
    }
    
    if (_shouldPreprocess) {
        str = [JSTPreprocessor preprocessCode:str];
    }
      /*
    if (![[self jsController] evalJSString:str withScriptPath:[scriptURL path]]) {
        NSLog(@"Could not include '%@'", fileName);
    }
       */
}

- (void)print:(NSString*)s {
    
    if (_printController && [_printController respondsToSelector:@selector(print:)]) {
        [_printController print:s];
    }
    else {
        if (![s isKindOfClass:[NSString class]]) {
            s = [s description];
        }
        
        printf("%s\n", [s UTF8String]);
    }
}


+ (id)applicationOnPort:(NSString*)port {
    
    NSConnection *conn  = nil;
    NSUInteger tries    = 0;
    
    while (!conn && tries < 10) {
        
        conn = [NSConnection connectionWithRegisteredName:port host:nil];
        tries++;
        if (!conn) {
            debug(@"Sleeping, waiting for %@ to open", port);
            sleep(1);
        }
    }
    
    if (!conn) {
        NSBeep();
        NSLog(@"Could not find a JSTalk connection to %@", port);
    }
    
    return [conn rootProxy];
}

+ (id)application:(NSString*)app {
    
    NSString *appPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:app];
    
    if (!appPath) {
        NSLog(@"Could not find application '%@'", app);
        // fixme: why are we returning a bool?
        return [NSNumber numberWithBool:NO];
    }
    
    NSBundle *appBundle = [NSBundle bundleWithPath:appPath];
    NSString *bundleId  = [appBundle bundleIdentifier];
    
    // make sure it's running
	NSArray *runningApps = [[[NSWorkspace sharedWorkspace] launchedApplications] valueForKey:@"NSApplicationBundleIdentifier"];
    
	if (![runningApps containsObject:bundleId]) {
        BOOL launched = [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:bundleId
                                                                             options:NSWorkspaceLaunchWithoutActivation | NSWorkspaceLaunchAsync
                                                      additionalEventParamDescriptor:nil
                                                                    launchIdentifier:nil];
        if (!launched) {
            NSLog(@"Could not open up %@", appPath);
            return nil;
        }
    }
    
    
    return [self applicationOnPort:[NSString stringWithFormat:@"%@.JSTalk", bundleId]];
}

+ (id)app:(NSString*)app {
    return [self application:app];
}

+ (id)proxyForApp:(NSString*)app {
    return [self application:app];
}


@end



