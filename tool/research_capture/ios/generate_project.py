"""Deterministically generate the checked-in, dependency-free Xcode project."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def generate():
    objects = {}
    def add(name, value):
        objects[uid(name)] = value
        return uid(name)
    sources = sorted((ROOT/"BagdarCapture").glob("*.swift"))
    refs, builds = [], []
    for source in sources:
        ref = add(source.name, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{source.name}"; sourceTree = "<group>";}}')
        refs.append(ref)
        builds.append(add("build:"+source.name, f'{{isa = PBXBuildFile; fileRef = {ref};}}'))
    plist = add("plist", '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";}')
    app = add("app", '{isa = PBXFileReference; explicitFileType = wrapper.application; path = BagdarCapture.app; sourceTree = BUILT_PRODUCTS_DIR;}')
    test_product = add("test-product", '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = BagdarCaptureTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
    test_ref = add("test-source", '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CapturePackingTests.swift; sourceTree = "<group>";}')
    test_build = add("test-build", f'{{isa = PBXBuildFile; fileRef = {test_ref};}}')
    app_group = add("app-group", f'{{isa = PBXGroup; children = ({", ".join(refs+[plist])},); path = BagdarCapture; sourceTree = "<group>";}}')
    test_group = add("test-group", f'{{isa = PBXGroup; children = ({test_ref},); path = BagdarCaptureTests; sourceTree = "<group>";}}')
    products = add("products", f'{{isa = PBXGroup; children = ({app}, {test_product},); name = Products; sourceTree = "<group>";}}')
    main = add("main-group", f'{{isa = PBXGroup; children = ({app_group}, {test_group}, {products},); sourceTree = "<group>";}}')
    source_phase = add("source-phase", f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(builds)},); runOnlyForDeploymentPostprocessing = 0;}}')
    test_phase = add("test-phase", f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({test_build},); runOnlyForDeploymentPostprocessing = 0;}}')
    frameworks = add("frameworks", '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
    resources = add("resources", '{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
    def configs(prefix, extra):
        result = []
        for name in ("Debug", "Release"):
            debug = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf;' if name == "Debug" else 'SWIFT_COMPILATION_MODE = wholemodule; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
            result.append(add(prefix+name, '{isa = XCBuildConfiguration; name = '+name+'; buildSettings = {'+debug+extra+'};}'))
        return add(prefix+"configs", f'{{isa = XCConfigurationList; buildConfigurations = ({", ".join(result)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
    project_configs = configs("project", 'CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 15.0; SWIFT_VERSION = 5.0;')
    app_configs = configs("app", 'PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = org.bagdar.research.capture; INFOPLIST_FILE = BagdarCapture/Info.plist; BAGDAR_CAPTURE_SOURCE_ID = "unfrozen-development"; CODE_SIGN_STYLE = Automatic; TARGETED_DEVICE_FAMILY = 1; SWIFT_EMIT_LOC_STRINGS = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";')
    test_configs = configs("test", 'PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = org.bagdar.research.capture.tests; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic; TARGETED_DEVICE_FAMILY = 1; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/BagdarCapture.app/BagdarCapture"; BUNDLE_LOADER = "$(TEST_HOST)"; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";')
    app_target = add("app-target", f'{{isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = ({source_phase}, {frameworks}, {resources},); buildRules = (); dependencies = (); name = BagdarCapture; productName = BagdarCapture; productReference = {app}; productType = "com.apple.product-type.application";}}')
    proxy = add("proxy", f'{{isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = BagdarCapture;}}')
    dependency = add("dependency", f'{{isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};}}')
    test_target = add("test-target", f'{{isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = ({test_phase},); buildRules = (); dependencies = ({dependency},); name = BagdarCaptureTests; productName = BagdarCaptureTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";}}')
    project = add("project", f'{{isa = PBXProject; attributes = {{LastUpgradeCheck = 1600; TargetAttributes = {{{test_target} = {{TestTargetID = {app_target};}};}};}}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({app_target}, {test_target},);}}')
    directory = ROOT/"BagdarCapture.xcodeproj"
    directory.mkdir(exist_ok=True)
    (directory/"project.pbxproj").write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+
        '\n'.join(f'{key} = {value};' for key, value in objects.items())+
        f'\n}}; rootObject = {project};}}\n', encoding="utf-8")
    schemes = directory/"xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    def reference(identifier, product, name):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:BagdarCapture.xcodeproj"/>'
    app_ref = reference(app_target, "BagdarCapture.app", "BagdarCapture")
    tests = reference(test_target, "BagdarCaptureTests.xctest", "BagdarCaptureTests")
    (schemes/"BagdarCapture.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{tests}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO">{tests}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n''', encoding="utf-8")


if __name__ == "__main__":
    generate()
