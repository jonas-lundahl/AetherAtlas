#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generation; rerun after adding source files."""
from pathlib import Path
import hashlib, json
import xml.etree.ElementTree as ET
root = Path(__file__).resolve().parent.parent
objects = {}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key, body): objects[uid(key)] = body; return uid(key)
def q(s): return json.dumps(str(s))
def arr(ids): return '(' + ', '.join(ids) + (',' if ids else '') + ')'
def source_phase(name, paths):
    builds=[]
    refs=[]
    for path in paths:
        ref=add('file:'+str(path),f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = SOURCE_ROOT;')
        refs.append(ref)
        builds.append(add('build:'+name+str(path), f'isa = PBXBuildFile; fileRef = {ref};'))
    phase=add(name+':sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;')
    return phase,refs
app_files=sorted(str(p.relative_to(root)) for p in (root/'Sources').rglob('*.swift'))
test_files=sorted(str(p.relative_to(root)) for p in (root/'Tests/AetherCoreTests').glob('*.swift'))
ui_files=sorted(str(p.relative_to(root)) for p in (root/'Tests/AetherAtlasUITests').glob('*.swift'))
app_phase,app_refs=source_phase('app',app_files)
test_phase,test_refs=source_phase('test',test_files)
ui_phase,ui_refs=source_phase('ui',ui_files)
fixtures=add('fixtures','isa = PBXFileReference; lastKnownFileType = folder; path = Tests/AetherCoreTests/Fixtures; sourceTree = SOURCE_ROOT;')
fixture_build=add('fixtures-build',f'isa = PBXBuildFile; fileRef = {fixtures};')
test_resource=add('test-resource',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({fixture_build},); runOnlyForDeploymentPostprocessing = 0;')
assets=add('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = SOURCE_ROOT;')
assets_build=add('assets-build',f'isa = PBXBuildFile; fileRef = {assets};')
game_data=add('game-data','isa = PBXFileReference; lastKnownFileType = text.json; path = Sources/AetherCore/Resources/GameDataIndex.json; sourceTree = SOURCE_ROOT;')
game_data_build=add('game-data-build',f'isa = PBXBuildFile; fileRef = {game_data};')
app_resource=add('app-resource',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assets_build}, {game_data_build},); runOnlyForDeploymentPostprocessing = 0;')
app_product=add('app-product','isa = PBXFileReference; explicitFileType = wrapper.application; path = AetherAtlas.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product=add('test-product','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AetherCoreTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_product=add('ui-product','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AetherAtlasUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products=add('products',f'isa = PBXGroup; children = ({app_product}, {test_product}, {ui_product},); name = Products; sourceTree = "<group>";')
source_group=add('source-group',f'isa = PBXGroup; children = {arr(app_refs+[assets,game_data])}; name = Sources; sourceTree = "<group>";')
test_group=add('test-group',f'isa = PBXGroup; children = {arr(test_refs+[fixtures]+ui_refs)}; name = Tests; sourceTree = "<group>";')
main=add('main-group',f'isa = PBXGroup; children = ({source_group}, {test_group}, {products},); sourceTree = "<group>";')
def configs(name,extra):
    ids=[]
    for mode in ['Debug','Release']:
        settings={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'26.0','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','CLANG_ENABLE_MODULES':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','ONLY_ACTIVE_ARCH':'YES' if mode=='Debug' else 'NO','ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '', 'CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Automatic'} | extra
        ids.append(add(name+mode,'isa = XCBuildConfiguration; name = '+mode+'; buildSettings = {'+' '.join(f'{k} = {q(v)};' for k,v in settings.items())+'};'))
    return add(name+'configs',f'isa = XCConfigurationList; buildConfigurations = {arr(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project_config=configs('project',{})
app_config=configs('app',{'PRODUCT_NAME':'AetherAtlas','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','PRODUCT_BUNDLE_IDENTIFIER':'dev.aetheratlas.mac','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_CFBundleDisplayName':'Aether Atlas','INFOPLIST_KEY_CFBundleName':'Aether Atlas','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.reference','INFOPLIST_KEY_NSHumanReadableCopyright':'FINAL FANTASY XIV © SQUARE ENIX. Independent community tool.','MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'1','ENABLE_APP_SANDBOX':'YES','ENABLE_OUTGOING_NETWORK_CONNECTIONS':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks'})
test_config=configs('test',{'PRODUCT_NAME':'AetherCoreTests','PRODUCT_BUNDLE_IDENTIFIER':'dev.aetheratlas.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/AetherAtlas.app/Contents/MacOS/AetherAtlas','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @loader_path/../Frameworks @executable_path/../Frameworks'})
ui_config=configs('ui',{'PRODUCT_NAME':'AetherAtlasUITests','PRODUCT_BUNDLE_IDENTIFIER':'dev.aetheratlas.uitests','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'AetherAtlas'})
app=add('app-target',f'isa = PBXNativeTarget; buildConfigurationList = {app_config}; buildPhases = ({app_phase}, {app_resource},); buildRules = (); dependencies = (); name = AetherAtlas; productName = AetherAtlas; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy=add('test-proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = AetherAtlas;')
dep=add('test-dep',f'isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};')
test=add('test-target',f'isa = PBXNativeTarget; buildConfigurationList = {test_config}; buildPhases = ({test_phase}, {test_resource},); buildRules = (); dependencies = ({dep},); name = AetherCoreTests; productName = AetherCoreTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
ui=add('ui-target',f'isa = PBXNativeTarget; buildConfigurationList = {ui_config}; buildPhases = ({ui_phase},); buildRules = (); dependencies = ({dep},); name = AetherAtlasUITests; productName = AetherAtlasUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
project=add('project',f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2710; LastUpgradeCheck = 2710;}}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({app}, {test}, {ui},);')
text='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = {'+v+'};' for k,v in objects.items())+'\n}; rootObject = '+project+'; }\n'
(root/'AetherAtlas.xcodeproj/project.pbxproj').write_text(text)
ref=lambda ident,name: f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:AetherAtlas.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app,'AetherAtlas.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test,'AetherCoreTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'AetherAtlas.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'AetherAtlas.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
def write_scheme(path, content):
    # Retain existing formatting when regeneration does not change scheme settings.
    if path.exists() and ET.canonicalize(path.read_text(), strip_text=True) == ET.canonicalize(content, strip_text=True):
        return
    path.write_text(content)

write_scheme(root/'AetherAtlas.xcodeproj/xcshareddata/xcschemes/AetherAtlas.xcscheme',scheme)

ui_scheme=scheme.replace(ref(test,'AetherCoreTests.xctest'),ref(ui,'AetherAtlasUITests.xctest'))
write_scheme(root/'AetherAtlas.xcodeproj/xcshareddata/xcschemes/AetherAtlas-UI.xcscheme',ui_scheme)
