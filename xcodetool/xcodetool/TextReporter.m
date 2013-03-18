
#import "TextReporter.h"
#import "NSFileHandle+Print.h"

#import <sys/ioctl.h>
#import <unistd.h>

@interface ReportWriter : NSObject
{
}

@property (nonatomic, assign) NSInteger indent;
@property (nonatomic, assign) NSInteger savedIndent;
@property (nonatomic, assign) BOOL useANSI;
@property (nonatomic, retain) NSFileHandle *outputHandle;
@property (nonatomic, retain) NSString *lastLineUpdate;

- (id)initWithOutputHandle:(NSFileHandle *)outputHandle;

@end

@implementation ReportWriter

- (id)initWithOutputHandle:(NSFileHandle *)outputHandle
{
  if (self = [super init]) {
    self.outputHandle = outputHandle;
    _indent = 0;
    _savedIndent = -1;
  }
  return self;
}

- (void)dealloc
{
  self.outputHandle = nil;
  [super dealloc];
}

- (void)increaseIndent
{
  _indent++;
}

- (void)decreaseIndent
{
  assert(_indent > 0);
  _indent--;
}

- (void)disableIndent
{
  _savedIndent = _indent;
  _indent = 0;
}

- (void)enableIndent
{
  _indent = _savedIndent;
}

- (NSString *)formattedStringWithFormat:(NSString *)format arguments:(va_list)argList
{
  NSMutableString *str = [[[NSMutableString alloc] initWithFormat:format arguments:argList] autorelease];
  
  NSDictionary *ansiTags = @{@"<red>": @"\x1b[31m",
                             @"<green>": @"\x1b[32m",
                             @"<yellow>": @"\x1b[33m",
                             @"<blue>": @"\x1b[34m",
                             @"<magenta>": @"\x1b[35m",
                             @"<cyan>": @"\x1b[36m",
                             @"<white>": @"\x1b[37m",
                             @"<bold>": @"\x1b[1m",
                             @"<faint>": @"\x1b[2m",
                             @"<underline>": @"\x1b[4m",
                             @"<reset>": @"\x1b[0m",
                             };
  
  for (NSString *ansiTag in [ansiTags allKeys]) {
    NSString *replaceWith = self.useANSI ? ansiTags[ansiTag] : @"";
    [str replaceOccurrencesOfString:ansiTag withString:replaceWith options:0 range:NSMakeRange(0, [str length])];
  }

  if (_indent > 0) {
    [str insertString:[@"" stringByPaddingToLength:(_indent * 2) withString:@" " startingAtIndex:0]
              atIndex:0];
  }
  
  return str;
}

- (void)printString:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2)
{
  va_list args;
  va_start(args, format);
  NSString *str = [self formattedStringWithFormat:format arguments:args];
  [self.outputHandle writeData:[str dataUsingEncoding:NSUTF8StringEncoding]];
  va_end(args);
}

- (void)printNewline
{
  if (self.lastLineUpdate != nil && !_useANSI) {
    [self.outputHandle writeData:[self.lastLineUpdate dataUsingEncoding:NSUTF8StringEncoding]];
    self.lastLineUpdate = nil;
  }
  [self.outputHandle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)updateLineWithFormat:(NSString *)format arguments:(va_list)argList
{
  NSString *line = [self formattedStringWithFormat:format arguments:argList];;

  if (_useANSI) {
    [self.outputHandle writeData:[@"\r" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.outputHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
  } else {
    self.lastLineUpdate = line;
  }
}

- (void)updateLine:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2)
{
  va_list args;
  va_start(args, format);
  [self updateLineWithFormat:format arguments:args];
  va_end(args);
}

- (void)printLine:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2)
{
  va_list args;
  va_start(args, format);
  [self updateLineWithFormat:format arguments:args];
  [self printNewline];
  va_end(args);
}

@end

@implementation TextReporter

- (id)initWithOutputPath:(NSString *)outputPath
{
  if (self = [super initWithOutputPath:outputPath]) {
    _isPretty = [self isKindOfClass:[PrettyTextReporter class]];
  }
  return self;
}

- (void)setupOutputHandleWithStandardOutput:(NSFileHandle *)standardOutput {
  [super setupOutputHandleWithStandardOutput:standardOutput];
  self.reportWriter = [[[ReportWriter alloc] initWithOutputHandle:standardOutput] autorelease];
  self.reportWriter.useANSI = _isPretty;
}

- (NSString *)passIndicatorString
{
  return _isPretty ? @"<green>\u2713<reset>" : @"~";
}

- (NSString *)failIndicatorString
{
  return _isPretty ? @"<red>\u2717<reset>" : @"X";
}

- (NSString *)emptyIndicatorString
{
  return _isPretty ? @" " : @" ";
}

- (void)printDividerWithDownLine:(BOOL)showDownLine
{
  struct winsize w = {0};
  ioctl(STDOUT_FILENO, TIOCGWINSZ, &w);
  int width = w.ws_col > 0 ? w.ws_col : 80;
  
  NSString *dashStr = nil;
  NSString *indicatorStr = nil;
  
  if ([self isKindOfClass:[PrettyTextReporter class]]) {
    dashStr = @"\u2501";
    indicatorStr = @"\u2533";
  } else {
    dashStr = @"-";
    indicatorStr = @"|";
  }

  NSString *dividier = [@"" stringByPaddingToLength:width withString:dashStr startingAtIndex:0];
  
  if (showDownLine) {
    dividier = [dividier stringByReplacingCharactersInRange:NSMakeRange(self.reportWriter.indent * 2, 1) withString:indicatorStr];
  }
  
  [self.reportWriter disableIndent];
  [self.reportWriter updateLine:@"<faint>%@<reset>", dividier];
  [self.reportWriter printNewline];
  [self.reportWriter enableIndent];
}

- (void)printDivider
{
  [self printDividerWithDownLine:NO];
}

- (NSString *)condensedBuildCommandTitle:(NSString *)title
{
  NSArray *parts = [title componentsSeparatedByString:@" "];
  NSMutableArray *newParts = [NSMutableArray array];
  
  for (NSString *part in parts) {
    if ([part rangeOfString:@"/"].length != 0) {
      // Looks like a path...
      [newParts addObject:[part lastPathComponent]];
    } else {
      [newParts addObject:part];
    }
  }
  
  return [newParts componentsJoinedByString:@" "];
}

- (void)beginXcodebuild:(NSDictionary *)event
{
  [self.reportWriter printLine:@"<bold>%@<reset> <underline>%@<reset>", event[@"command"], event[@"title"]];
  [self.reportWriter increaseIndent];
}

- (void)endXcodebuild:(NSDictionary *)event
{
  [self.reportWriter decreaseIndent];
  [self.reportWriter printNewline];
}

- (void)beginBuildTarget:(NSDictionary *)event
{
  [self.reportWriter printLine:@"<bold>%@<reset> / <bold>%@<reset> (%@)", event[@"project"], event[@"target"], event[@"configuration"]];
  [self.reportWriter increaseIndent];
}

- (void)endBuildTarget:(NSDictionary *)event
{
  [self.reportWriter decreaseIndent];
  [self.reportWriter printNewline];
}

- (void)beginBuildCommand:(NSDictionary *)event
{
  [self.reportWriter updateLine:@"%@ %@", [self emptyIndicatorString], [self condensedBuildCommandTitle:event[@"title"]]];
  self.currentBuildCommandEvent = event;
}

- (void)endBuildCommand:(NSDictionary *)event
{
  NSString *(^formattedBuildDuration)(float) = ^(float duration){
    NSString *color = nil;

    if (duration <= 0.05f) {
      color = @"<faint><green>";
    } else if (duration <= 0.2f) {
      color = @"<green>";
    } else if (duration <= 0.5f) {
      color = @"<yellow>";
    } else {
      color = @"<red>";
    }

    return [NSString stringWithFormat:@"%@(%d ms)<reset>", color, (int)(duration * 1000)];
  };

  BOOL succeeded = [event[@"succeeded"] boolValue];
  NSString *indicator = succeeded ? [self passIndicatorString] : [self failIndicatorString];

  [self.reportWriter updateLine:@"%@ %@ %@",
   indicator,
   [self condensedBuildCommandTitle:event[@"title"]],
   formattedBuildDuration([event[@"duration"] floatValue])];
  [self.reportWriter printNewline];

  if (!succeeded) {
    [self printDivider];
    [self.reportWriter disableIndent];

    [self.reportWriter printLine:@"<faint>%@<reset>", self.currentBuildCommandEvent[@"command"]];
    [self.reportWriter printLine:@"%@",
     [event[@"failureReason"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    
    [self.reportWriter enableIndent];
    [self printDivider];
  }

  self.currentBuildCommandEvent = event;
}

- (void)beginOctest:(NSDictionary *)event
{
  [self.reportWriter printLine:@"<bold>run-test<reset> <underline>%@<reset> %@",
   event[@"title"],
   (event[@"titleExtra"] != nil) ? [NSString stringWithFormat:@"(%@)", event[@"titleExtra"]] : @""];
  [self.reportWriter increaseIndent];
}

- (void)endOctest:(NSDictionary *)event
{
  [self.reportWriter decreaseIndent];
  
  if (![event[@"succeeded"] boolValue] && ![event[@"failureReason"] isEqual:[NSNull null]]) {
    [self.reportWriter printLine:@"<bold>failed<reset>: %@", event[@"failureReason"]];
  }
}

- (void)beginTestSuite:(NSDictionary *)event
{
  NSString *suite = event[@"suite"];
  
  if (![suite isEqualToString:@"All tests"] && ![suite hasSuffix:@".octest(Tests)"]) {
    if ([suite hasPrefix:@"/"]) {
      suite = [suite lastPathComponent];
    }
    
    [self.reportWriter printLine:@"<bold>suite<reset> <underline>%@<reset>", suite];
    [self.reportWriter increaseIndent];
  }
}

- (void)endTestSuite:(NSDictionary *)event
{
  NSString *suite = event[@"suite"];
  int testCaseCount = [event[@"testCaseCount"] intValue];
  int totalFailureCount = [event[@"totalFailureCount"] intValue];
  
  if (![suite isEqualToString:@"All tests"] && ![suite hasSuffix:@".octest(Tests)"]) {
    [self.reportWriter printLine:@"<bold>%d of %d tests passed %@<reset>",
     (testCaseCount - totalFailureCount),
     testCaseCount,
     [self formattedTestDuration:[event[@"totalDuration"] floatValue] withColor:NO]
     ];
    [self.reportWriter decreaseIndent];
    [self.reportWriter printString:@"\n"];
  } else if ([suite isEqualToString:@"All tests"] && totalFailureCount > 0) {
    [self.reportWriter printLine:@"<bold>%d of %d tests passed %@<reset>",
     (testCaseCount - totalFailureCount),
     testCaseCount,
     [self formattedTestDuration:[event[@"totalDuration"] floatValue] withColor:NO]
     ];
    [self.reportWriter printString:@"\n"];
  }
}

- (void)beginTest:(NSDictionary *)event
{
  [self.reportWriter updateLine:@"%@ %@", [self emptyIndicatorString], event[@"test"]];
  self.testHadOutput = NO;
}

- (void)testOutput:(NSDictionary *)event {
  if (!self.testHadOutput) {
    [self.reportWriter printNewline];
    [self printDivider];
  }
  
  [self.reportWriter disableIndent];
  [self.reportWriter printString:@"<faint>%@<reset>", event[@"output"]];
  [self.reportWriter enableIndent];

  self.testHadOutput = YES;
  self.testOutputEndsInNewline = [event[@"output"] hasSuffix:@"\n"];
}

- (NSString *)formattedTestDuration:(float)duration withColor:(BOOL)withColor
{
  NSString *color = nil;
  
  if (duration <= 0.05f) {
    color = @"<faint><green>";
  } else if (duration <= 0.2f) {
    color = @"<green>";
  } else if (duration <= 0.5f) {
    color = @"<yellow>";
  } else {
    color = @"<red>";
  }
  
  if (withColor) {
    return [NSString stringWithFormat:@"%@(%d ms)<reset>", color, (int)(duration * 1000)];
  } else {
    return [NSString stringWithFormat:@"(%d ms)", (int)(duration * 1000)];
  }
};

- (void)endTest:(NSDictionary *)event
{
  BOOL showInfo = ![event[@"succeeded"] boolValue] || ([event[@"output"] length] > 0);
  NSString *indicator = nil;
  
  if ([event[@"succeeded"] boolValue]) {
    indicator = [self passIndicatorString];
  } else {
    indicator = [self failIndicatorString];
  }

  if (showInfo) {
    if (!self.testHadOutput) {
      [self.reportWriter printNewline];
      [self printDivider];
    }
    
    [self.reportWriter disableIndent];
    
    // Show exception, if any.
    NSDictionary *exception = event[@"exception"];
    if (exception) {
      [self.reportWriter printLine:@"%@:%d: %@", exception[@"filePathInProject"], [exception[@"lineNumber"] intValue], exception[@"reason"]];
    }
    
    [self.reportWriter enableIndent];
    [self printDividerWithDownLine:YES];
  } else {
    [self.reportWriter printString:@"\r"];
  }
  
  [self.reportWriter printLine:@"%@ %@ %@",
   indicator,
   event[@"test"],
   [self formattedTestDuration:[event[@"totalDuration"] floatValue] withColor:YES]
   ];
}

@end

@implementation PrettyTextReporter
@end

@implementation PlainTextReporter
@end