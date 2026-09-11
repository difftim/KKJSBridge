import Cocoa
import WebKit
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let origin=CommandLine.arguments[2]
let recovery=try String(contentsOf:root.appendingPathComponent("KKJSBridge/KKJSBridge/JS/KKJSBridgeFormBodyRecovery.js"),encoding:.utf8)
final class WireRunner:NSObject,WKNavigationDelegate,WKScriptMessageHandler {
 var web:WKWebView!
 var window:NSWindow!
 var cached:String?
 var received:String?
 func start() {
  let config=WKWebViewConfiguration()
  config.userContentController.add(self,name:"wireBody")
  let shim="window.KKJSBridgeConfig={ajaxHook:true};window.KKJSBridge={call:(m,n,d)=>webkit.messageHandlers.wireBody.postMessage(d)};"
  config.userContentController.addUserScript(WKUserScript(source:shim+recovery+"window.KKJSBridgeInstallFormBodyRecovery({scope:'wire-test',rules:[{sourceOrigin:'\(origin)',sourcePathPrefix:'/pages/',targetOrigin:'\(origin)',targetPath:'/submit'}]});",injectionTime:.atDocumentStart,forMainFrameOnly:true))
  web=WKWebView(frame:NSRect(x:0,y:0,width:400,height:300),configuration:config);web.navigationDelegate=self
  window=NSWindow(contentRect:web.frame,styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=web
  web.load(URLRequest(url:URL(string:origin+"/pages/form")!))
 }
 func webView(_ web:WKWebView,didFinish navigation:WKNavigation!) {
  if web.url!.path=="/pages/form" {web.evaluateJavaScript("document.getElementById('go').click()",completionHandler:nil)}
  else {web.evaluateJavaScript("document.body.textContent") { value,error in
   self.received=value as? String;self.verify()
  }}
 }
 func userContentController(_ c:WKUserContentController,didReceive message:WKScriptMessage) {
  guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.path == "/pages/form" else {
   print("FAIL native frame source does not identify the sending document");exit(1)
  }
  cached=(message.body as! [String:String])["value"];verify()
 }
 func verify() {
  guard let cached,let received else{return}
  guard cached==received else {print("FAIL wire body differs: cached=\(cached) browser=\(received)");exit(1)}
  print("PASS: recovered body equals actual browser POST after formdata listeners");exit(0)
 }
}
let runner=WireRunner();runner.start()
DispatchQueue.main.asyncAfter(deadline:.now()+10){print("FAIL wire test timed out");exit(1)}
app.run()
