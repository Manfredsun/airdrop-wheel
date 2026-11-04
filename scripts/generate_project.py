#!/usr/bin/env python3
"""Deterministic Xcode project generator for AirDrop Wheel."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
objects = {}

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(key_name, isa, **values):
    key = uid(key_name)
    objects[key] = dict(isa=isa, **values)
    return key

def config(name, settings):
    return add(name, "XCBuildConfiguration", buildSettings=settings, name=name.split("/")[-1])

def configs(name, settings):
    return add(name + "/configs", "XCConfigurationList", buildConfigurations=[
        config(name + "/Debug", dict(settings, SWIFT_OPTIMIZATION_LEVEL="-Onone", ENABLE_TESTABILITY="YES", DEBUG_INFORMATION_FORMAT="dwarf", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG")),
        config(name + "/Release", dict(settings, SWIFT_OPTIMIZATION_LEVEL="-O", DEBUG_INFORMATION_FORMAT="dwarf-with-dsym"))
    ], defaultConfigurationIsVisible="0", defaultConfigurationName="Debug")

sources = sorted((root / "App/Sources").rglob("*.swift"))
resources = [root / "App/Resources/Assets.xcassets"]
extras = [
    root / "Config/Info.plist",
    root / "design.md",
    root / "README.md",
]

refs = {}
for path in sources + extras:
    relative = str(path.relative_to(root))
    file_type = "sourcecode.swift" if path.suffix == ".swift" else "text"
    refs[relative] = add(relative, "PBXFileReference", path=relative, sourceTree="<group>", lastKnownFileType=file_type)

for path in resources:
    relative = str(path.relative_to(root))
    refs[relative] = add(relative, "PBXFileReference", path=relative, sourceTree="<group>", lastKnownFileType="folder.assetcatalog")

app_product = add("product/app", "PBXFileReference", explicitFileType="wrapper.application", path="AirDrop Wheel.app", sourceTree="BUILT_PRODUCTS_DIR")
products = add("products", "PBXGroup", children=[app_product], name="Products", sourceTree="<group>")
main = add("main", "PBXGroup", children=list(refs.values()) + [products], sourceTree="<group>")

def sources_phase(name, paths):
    files = [add(name + "/" + str(p.relative_to(root)), "PBXBuildFile", fileRef=refs[str(p.relative_to(root))]) for p in paths]
    return add(name, "PBXSourcesBuildPhase", buildActionMask="2147483647", files=files, runOnlyForDeploymentPostprocessing="0")

def resources_phase(name, paths):
    files = [add(name + "/" + str(p.relative_to(root)), "PBXBuildFile", fileRef=refs[str(p.relative_to(root))]) for p in paths]
    return add(name, "PBXResourcesBuildPhase", buildActionMask="2147483647", files=files, runOnlyForDeploymentPostprocessing="0")

def frameworks_phase(name):
    return add(name, "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")

app_id, project_id = uid("app"), uid("project")

common = dict(
    SWIFT_VERSION="5.0",
    MACOSX_DEPLOYMENT_TARGET="14.0",
    SDKROOT="macosx",
    CLANG_ENABLE_MODULES="YES",
    SWIFT_STRICT_CONCURRENCY="minimal",
)

app_settings = dict(
    common,
    PRODUCT_NAME="AirDrop Wheel",
    PRODUCT_BUNDLE_IDENTIFIER="app.airdropwheel.macos",
    INFOPLIST_FILE="Config/Info.plist",
    GENERATE_INFOPLIST_FILE="NO",
    ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon",
    CODE_SIGN_IDENTITY="-",
    CODE_SIGN_STYLE="Manual",
    ENABLE_APP_SANDBOX="NO",
    ENABLE_HARDENED_RUNTIME="NO",
    LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/../Frameworks",
    MARKETING_VERSION="0.1.0",
    CURRENT_PROJECT_VERSION="1",
)

add("app", "PBXNativeTarget", 
    buildConfigurationList=configs("app", app_settings),
    buildPhases=[
        sources_phase("app/sources", sources),
        frameworks_phase("app/frameworks"),
        resources_phase("app/resources", resources),
    ],
    buildRules=[],
    dependencies=[],
    name="AirDrop Wheel",
    productName="AirDrop Wheel",
    productReference=app_product,
    productType="com.apple.product-type.application"
)

add("project", "PBXProject",
    attributes=dict(
        LastUpgradeCheck="2720",
        TargetAttributes={app_id: dict(CreatedOnToolsVersion="27.2")}
    ),
    buildConfigurationList=configs("project", common),
    compatibilityVersion="Xcode 14.0",
    developmentRegion="zh-Hant",
    knownRegions=["zh-Hant", "en", "Base"],
    mainGroup=main,
    productRefGroup=products,
    projectDirPath="",
    projectRoot="",
    targets=[app_id]
)

def pbx(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + json.dumps(str(k)) + " = " + pbx(v, indent + 1) + ";\n" for k, v in sorted(value.items())) + "\t" * indent + "}"
    if isinstance(value, list):
        return "(" + ", ".join(pbx(v, indent) for v in value) + ")"
    return json.dumps(str(value))

project = root / "AirDrop Wheel.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + pbx(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project_id)) + "\n")

scheme = project / "xcshareddata/xcschemes"
scheme.mkdir(parents=True, exist_ok=True)

app_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="AirDrop Wheel.app" BlueprintName="AirDrop Wheel" ReferencedContainer="container:AirDrop Wheel.xcodeproj"/>'

(scheme / "AirDrop Wheel.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2720" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

print("Generated AirDrop Wheel.xcodeproj successfully")
