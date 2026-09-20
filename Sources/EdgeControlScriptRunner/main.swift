import Foundation

// Runs one AppleScript for EdgeControl and exits.
//
// EdgeControl used to hand its scripts to /usr/bin/osascript. osascript checks
// in with the window server as a foreground app once it sends an Apple event,
// so a poll every five seconds flashed an icon in the Dock over and over. This
// bundle is LSBackgroundOnly, so the system never gives it one.
//
// Running the scripts inside EdgeControl is not the answer either: NSAppleScript
// is main-thread only, and a query can take most of a second — far longer while
// a browser hangs or an Automation prompt sits unanswered — which would stall
// the dashboard. Out here the main thread is ours, and EdgeControl keeps its
// deadline because it can still kill the process.
//
// Contract, the same shape as `osascript -e`: the script source is the only
// argument, the result is written to stdout, and a script that raises an error
// exits 1 with the message on stderr.

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: EdgeControlScriptRunner <applescript-source>\n".utf8))
    exit(EX_USAGE)
}

guard let script = NSAppleScript(source: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("could not create the script\n".utf8))
    exit(EX_DATAERR)
}

var errorInfo: NSDictionary?
// Annotated non-optional in the SDK but nil for a script that returns nothing;
// widening it here is what keeps that case from trapping.
let result = script.executeAndReturnError(&errorInfo) as NSAppleEventDescriptor?

if let errorInfo {
    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "script failed"
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

print(result?.stringValue ?? "")
