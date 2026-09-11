import Cocoa
import WebKit

// Exercises real WebKit event dispatch and form navigation with synthetic credentials.
// Network navigation is canceled; the cached URL-encoded body is inspected locally.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let recovery = try String(contentsOf: root.appendingPathComponent("KKJSBridge/KKJSBridge/JS/KKJSBridgeFormBodyRecovery.js"), encoding: .utf8)
let sso = try String(contentsOf: root.appendingPathComponent("Tests/FormBodyRecovery/form_submit.fixture.js"), encoding: .utf8)
struct Case {
 let name: String
 var setup = ""
 var trigger = "document.getElementById('go').click()"
 var navigation = true
 var recovered = true
 var cacheWorks = true
 var extraHTML = ""
 var extraJS = ""
 var enabled = true
 var base = "https://sso.difft.org/ui/login/test"
}
let cases: [Case] = [
 Case(name: "button"),
 Case(name: "old device send code", extraHTML: "<input type='hidden' name='authRequestID' value='test-auth-request'><input type='hidden' name='oidcClientId' value=''>", extraJS: "document.querySelector('form').setAttribute('action','/ui/login/otp/olddevice');document.querySelector('[name=loginName]').type='hidden'", base: "https://sso.difft.org/ui/login/otp/olddevice?authRequestID=test-auth-request"),
 Case(name: "requestSubmit", trigger: "document.querySelector('form').requestSubmit(document.getElementById('go'))"),
 Case(name: "invalid", setup: "document.querySelector('[name=loginName]').value=''", navigation: false),
 Case(name: "form cancels", setup: "document.querySelector('form').addEventListener('submit',e=>e.preventDefault())", navigation: false),
 Case(name: "later window cancels", setup: "window.addEventListener('submit',e=>e.preventDefault())", navigation: false),
 Case(name: "double click", trigger: "document.getElementById('go').click();document.getElementById('go').click()"),
 Case(name: "inspect FormData in handler", setup: "document.querySelector('form').addEventListener('submit',e=>new FormData(e.target))"),
 Case(name: "formdata modified by page", setup: "document.querySelector('form').addEventListener('formdata',e=>e.formData.append('pageAdded','yes'))"),
 Case(name: "window formdata modified late", setup: "window.addEventListener('formdata',e=>e.formData.append('pageAdded','yes'))"),
 Case(name: "query bytes", setup: "document.querySelector('form').setAttribute('action','/ui/login/loginname?a=one%20two&a=%2f&plus=+&empty=&flag')"),
 Case(name: "empty fragment", setup: "document.querySelector('form').setAttribute('action','/ui/login/loginname#')", recovered: false),
 Case(name: "empty query", setup: "document.querySelector('form').setAttribute('action','/ui/login/loginname?')"),
 Case(name: "document cancels", setup: "document.addEventListener('submit',e=>e.preventDefault())", navigation: false),
 Case(name: "shadowed submit", extraHTML: "<input name='submit' value='shadow'>"),
 Case(name: "special charset field", recovered: false, extraHTML: "<input type='hidden' name='_charset_' value='legacy'>"),
 Case(name: "encoding override", setup: "document.querySelector('form').acceptCharset='ISO-8859-1'", recovered: false),
 Case(name: "oversized body", setup: "document.querySelector('[name=loginName]').value='a'.repeat(65537)", recovered: false, cacheWorks: false),
 Case(name: "override action", extraHTML: "", extraJS: "document.getElementById('go').setAttribute('formaction','/ui/login/loginname');document.querySelector('form').setAttribute('action','/other')"),
 Case(name: "cache failure", recovered: false, cacheWorks: false),
 Case(name: "feature off", recovered: false, enabled: false),
 Case(name: "other domain", recovered: false, base: "https://example.com/ui/login/test"),
 Case(name: "other action", setup: "document.querySelector('form').setAttribute('action','/other')", recovered: false),
 Case(name: "unsupported encoding", setup: "document.querySelector('form').enctype='multipart/form-data'", recovered: false),
 Case(name: "file form", recovered: false, extraHTML: "<input type='file' name='file'>"),
 Case(name: "explicit submit", trigger: "HTMLFormElement.prototype.submit.call(document.querySelector('form'))", recovered: false)
]
final class Runner: NSObject, WKNavigationDelegate, WKUIDelegate {
 var web: WKWebView!
 var window: NSWindow!
 var index = -1
 var generation = 0
 var bodies: [String: String] = [:]
 var navigations = 0
 var submission: URLRequest?
 var cacheCalls = 0
 var current: Case { cases[index] }
 func require(_ condition: Bool, _ message: String) {
  if !condition { print("FAIL \(current.name): \(message)"); exit(1) }
 }
 func next() {
  index += 1; generation += 1
  if index == cases.count { print("PASS: \(cases.count) real WKWebView scenarios"); scopeRunner.start(); return }
  bodies = [:]; navigations = 0; cacheCalls = 0; submission = nil
  web?.navigationDelegate = nil; web?.uiDelegate = nil
  let config = WKWebViewConfiguration()
  let shim = """
  window.KKJSBridgeConfig={ajaxHook:true};
  window._KKJSBridgeXHR={generateXHRRequestId:()=>String(Date.now())};
  window.KKJSBridge={call:(module,method,data)=>JSON.parse(prompt('KKJSBridge',JSON.stringify(data))||'null')};
  """
  config.userContentController.addUserScript(WKUserScript(source: shim + recovery + (current.enabled ? "window.KKJSBridgeInstallFormBodyRecovery({scope:'test-scope',rules:[{sourceOrigin:'https://sso.difft.org',sourcePathPrefix:'/ui/login/',targetOrigin:'https://sso.difft.org',targetPath:'/ui/login/loginname'},{sourceOrigin:'https://sso.difft.org',sourcePathPrefix:'/ui/login/',targetOrigin:'https://sso.difft.org',targetPath:'/ui/login/otp/olddevice'}]});" : ""),injectionTime:.atDocumentStart,forMainFrameOnly:true))
  web=WKWebView(frame:NSRect(x:0,y:0,width:600,height:400),configuration:config)
  web.navigationDelegate=self;web.uiDelegate=self
  if window == nil { window=NSWindow(contentRect:web.frame,styleMask:[.borderless],backing:.buffered,defer:false) }
  window.contentView=web
  let html = """
  <!doctype html><meta charset='utf-8'>
  <form action='/ui/login/loginname' method='POST'>
  <input name='gorilla.csrf.Token' value='dummy+token/='>
  <input name='loginName' required value='tester+测试@example.com'>
  <input name='repeat' value='first'><input name='repeat' value='second'>
  <textarea name='notes'>line1\nline2</textarea>
  <input name='disabledField' value='not-sent' disabled>
  \(current.extraHTML)
  <button id='go' type='submit' name='action' value='send'>Continue</button></form>
  <script>\(sso)\n disableDoubleSubmit(document.querySelector('form'),document.getElementById('go'));\(current.extraJS)</script>
  """
  web.loadHTMLString(html,baseURL:URL(string:current.base)!)
 }
 func webView(_ w:WKWebView,didFinish navigation:WKNavigation!) {
  let g=generation
  w.evaluateJavaScript(current.setup + ";" + current.trigger) { _,error in
   if let error { self.require(false,"JS \(error)") }
   DispatchQueue.main.asyncAfter(deadline:.now()+0.4) {
    guard g==self.generation else{return}
    self.require(self.navigations == (self.current.navigation ? 1 : 0),"navigation count \(self.navigations)")
    if !self.current.navigation { self.require(self.cacheCalls==0,"canceled/invalid form cached") }
    if let request = self.submission { self.check(request) }
    print("PASS \(self.current.name)");self.next()
   }
  }
 }
 func webView(_ w:WKWebView,runJavaScriptTextInputPanelWithPrompt prompt:String,defaultText:String?,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping(String?)->Void) {
  let data=try! JSONSerialization.jsonObject(with:Data(defaultText!.utf8)) as! [String:String]
  cacheCalls += 1
  if current.cacheWorks { bodies[data["requestId"]!] = data["value"]! }
  completionHandler(current.cacheWorks ? "{\"requestId\":\"\(data["requestId"]!)\",\"cached\":true}" : "null")
 }
 func webView(_ w:WKWebView,decidePolicyFor a:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
  guard a.request.httpMethod=="POST" else { decisionHandler(.allow);return }
  navigations += 1
  submission = a.request
  decisionHandler(.cancel)
 }
 func check(_ request: URLRequest) {
  let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems ?? []
  let id=query.first{$0.name=="KKJSBridge-FormBody"}?.value
  if current.recovered {
   require(id != nil,"request ID not carried on navigation")
   if current.name == "old device send code" {
    require(request.url?.path == "/ui/login/otp/olddevice", "second page target changed")
   }
   if current.name == "query bytes" {
    require(request.url!.absoluteString.contains("?a=one%20two&a=%2f&plus=+&empty=&flag&KKJSBridge-FormBody="), "query reserialized")
   }
   if current.name == "empty query" {require(request.url!.absoluteString.contains("?&KKJSBridge-FormBody="),"empty query changed")}

   require(query.contains{$0.name=="KKJSBridge-FormBody"},"missing fail-closed marker")
   require(cacheCalls==1,"cache count \(cacheCalls)")
   guard let body=bodies[id!] else { require(false,"missing cached body");return }
   var c=URLComponents();c.percentEncodedQuery=body.replacingOccurrences(of:"+",with:"%20")
   let fields=c.queryItems!
   require(fields.contains{$0.name=="gorilla.csrf.Token" && $0.value=="dummy+token/="},"CSRF altered")
   require(fields.contains{$0.name=="loginName" && $0.value=="tester+测试@example.com"},"Unicode or plus altered")
   require(fields.filter{$0.name=="repeat"}.map{$0.value!} == ["first","second"],"duplicates altered")
   require(fields.contains{$0.name=="action" && $0.value=="send"},"submitter missing")
   if current.name == "old device send code" {
    require(fields.contains{$0.name=="authRequestID" && $0.value=="test-auth-request"},"auth request field missing")
    require(fields.contains{$0.name=="oidcClientId" && $0.value==""},"empty client field missing")
   }
   require(fields.contains{$0.name=="notes" && $0.value=="line1\r\nline2"},"newline normalization")
   require(!fields.contains{$0.name=="disabledField"},"disabled control included")
   if current.name.contains("formdata modified") {require(fields.contains{$0.name=="pageAdded"},"page formdata change lost")}
  } else if !current.cacheWorks {
   require(id != nil && bodies.isEmpty,"failed cache must keep fail-closed marker")
  } else {require(id==nil && cacheCalls==0,"out of scope form changed")}
 }
}
// Two simultaneous WebViews deliberately share a nonce; only their host scopes differ.
final class ScopeRunner: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
 var windows: [NSWindow] = []
 var views: [WKWebView] = []
 var payloads: [String: String] = [:]
 var navigationTokens: Set<String> = []
 func start() {
  for scope in ["window-A", "window-B"] {
   let config = WKWebViewConfiguration()
   config.userContentController.add(self, name: "testBody")
   let script = """
   window.KKJSBridgeConfig={ajaxHook:true};
   Object.defineProperty(crypto,'getRandomValues',{value:a=>a.fill(7)});
   window.KKJSBridge={call:(m,n,data)=>window.webkit.messageHandlers.testBody.postMessage(data)};
   """ + recovery + "window.KKJSBridgeInstallFormBodyRecovery({scope:'\(scope)',rules:[{sourceOrigin:'https://forms.example',sourcePathPrefix:'/pages/',targetOrigin:'https://forms.example',targetPath:'/submit'}]});"
   config.userContentController.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentStart,forMainFrameOnly:true))
   let web=WKWebView(frame:NSRect(x:0,y:0,width:400,height:300),configuration:config)
   web.navigationDelegate=self
   let window=NSWindow(contentRect:web.frame,styleMask:[.borderless],backing:.buffered,defer:false)
   window.contentView=web;views.append(web);windows.append(window)
   web.loadHTMLString("<meta charset='utf-8'><form method='post' action='/submit'><input name='owner' value='\(scope)'><button id='go'>Send</button></form>",baseURL:URL(string:"https://forms.example/pages/form")!)
  }
 }
 func webView(_ web:WKWebView,didFinish navigation:WKNavigation!) {web.evaluateJavaScript("document.getElementById('go').click()",completionHandler:nil)}
 func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
  let data=message.body as! [String:String]
  payloads[data["requestId"]!]=data["value"]!
  verify()
 }
 func webView(_ web:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
  if action.request.httpMethod=="POST" {
   let token=URLComponents(url:action.request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first{$0.name=="KKJSBridge-FormBody"}!.value!
   navigationTokens.insert(token);decisionHandler(.cancel);verify()
  } else {decisionHandler(.allow)}
 }
 func verify() {
  guard payloads.count==2 && navigationTokens.count==2 else{return}
  for scope in ["window-A","window-B"] {
   let token=scope+"."+String(repeating:"07",count:16)
   guard navigationTokens.contains(token),payloads[token]=="owner="+scope else{print("FAIL window isolation");exit(1)}
  }
  print("PASS: simultaneous WebViews retain separate bodies with identical nonces");exit(0)
 }
}
let scopeRunner=ScopeRunner()
let runner=Runner();runner.next()
DispatchQueue.main.asyncAfter(deadline:.now()+60){print("FAIL timeout");exit(1)}
app.run()
