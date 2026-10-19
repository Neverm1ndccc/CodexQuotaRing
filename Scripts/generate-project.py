#!/usr/bin/env python3
"""Generate dependency-free native Xcode app + XCTest targets and shared scheme."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
objects={}
def uid(s):return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key,text):objects[uid(key)]=text;return uid(key)
def q(s):return '"'+s.replace('"','\\"')+'"'
def arr(xs):return '('+','.join(xs)+',)'
sources=sorted(str(p.relative_to(root)) for p in (root/'Sources').rglob('*.swift'))
tests=sorted(str(p.relative_to(root)) for p in (root/'Tests').glob('*.swift'))
refs=[];appfiles=[];testfiles=[]
for name in sources+tests:
 ref=add(name, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(name)}; sourceTree = SOURCE_ROOT; }}');refs.append(ref)
 build=add('build'+name,f'{{isa = PBXBuildFile; fileRef = {ref}; }}')
 (appfiles if name in sources else testfiles).append(build)
fixture=add('fixtures','{isa = PBXFileReference; lastKnownFileType = folder; path = Tests/Fixtures; sourceTree = SOURCE_ROOT; }');refs.append(fixture)
fixturebuild=add('buildfixtures',f'{{isa = PBXBuildFile; fileRef = {fixture}; }}')
appref=add('appref','{isa = PBXFileReference; explicitFileType = wrapper.application; path = CodexQuotaRing.app; sourceTree = BUILT_PRODUCTS_DIR; }')
testref=add('testref','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CodexQuotaRingTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
products=add('products',f'{{isa = PBXGroup; children = {arr([appref,testref])}; name = Products; sourceTree = "<group>"; }}')
main=add('main',f'{{isa = PBXGroup; children = {arr(refs+[products])}; sourceTree = "<group>"; }}')
def phase(key,kind,files):return add(key,f'{{isa = {kind}; buildActionMask = 2147483647; files = {arr(files) if files else "()"}; runOnlyForDeploymentPostprocessing = 0; }}')
appsrc=phase('appsrc','PBXSourcesBuildPhase',appfiles); testsrc=phase('testsrc','PBXSourcesBuildPhase',testfiles)
resources=phase('resources','PBXResourcesBuildPhase',[fixturebuild]);frameworks=phase('frameworks','PBXFrameworksBuildPhase',[])
def configs(key,extra):
 ids=[]
 for config in ['Debug','Release']:
  settings={'MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CODE_SIGN_STYLE':'Automatic','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O','ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if config=='Debug' else '','GCC_PREPROCESSOR_DEFINITIONS':'$(inherited)'}
  settings.update(extra)
  ids.append(add(key+config,'{isa = XCBuildConfiguration; buildSettings = {'+''.join(f'{k} = {q(v)};' for k,v in settings.items())+'}; name = '+config+'; }'))
 return add(key+'list',f'{{isa = XCConfigurationList; buildConfigurations = {arr(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
projectcfg=configs('projectcfg',{})
appcfg=configs('appcfg',{'PRODUCT_NAME':'CodexQuotaRing','PRODUCT_BUNDLE_IDENTIFIER':'com.local.CodexQuotaRing','INFOPLIST_FILE':'Resources/Info.plist','ENABLE_APP_SANDBOX':'NO','COMBINE_HIDPI_IMAGES':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks'})
testcfg=configs('testcfg',{'PRODUCT_NAME':'CodexQuotaRingTests','PRODUCT_BUNDLE_IDENTIFIER':'com.local.CodexQuotaRingTests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/CodexQuotaRing.app/Contents/MacOS/CodexQuotaRing','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'})
app=add('app',f'{{isa = PBXNativeTarget; buildConfigurationList = {appcfg}; buildPhases = {arr([appsrc,frameworks])}; buildRules = (); dependencies = (); name = CodexQuotaRing; productName = CodexQuotaRing; productReference = {appref}; productType = "com.apple.product-type.application"; }}')
proxy=add('proxy',f'{{isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = CodexQuotaRing; }}')
dep=add('dependency',f'{{isa = PBXTargetDependency; target = {app}; targetProxy = {proxy}; }}')
test=add('test',f'{{isa = PBXNativeTarget; buildConfigurationList = {testcfg}; buildPhases = {arr([testsrc,resources])}; buildRules = (); dependencies = {arr([dep])}; name = CodexQuotaRingTests; productName = CodexQuotaRingTests; productReference = {testref}; productType = "com.apple.product-type.bundle.unit-test"; }}')
proj=add('project',f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }}; buildConfigurationList = {projectcfg}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([app,test])}; }}')
d=root/'CodexQuotaRing.xcodeproj';d.mkdir(exist_ok=True)
(d/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+proj+'; }\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="CodexQuotaRing.app" BlueprintName="CodexQuotaRing" ReferencedContainer="container:CodexQuotaRing.xcodeproj"/></BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test}" BuildableName="CodexQuotaRingTests.xctest" BlueprintName="CodexQuotaRingTests" ReferencedContainer="container:CodexQuotaRing.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="CodexQuotaRing.app" BlueprintName="CodexQuotaRing" ReferencedContainer="container:CodexQuotaRing.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
s=d/'xcshareddata/xcschemes';s.mkdir(parents=True,exist_ok=True);(s/'CodexQuotaRing.xcscheme').write_text(scheme)
print(d)
