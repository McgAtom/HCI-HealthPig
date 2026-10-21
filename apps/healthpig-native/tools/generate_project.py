#!/usr/bin/env python3
"""Regenerate the two-target native Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OBJECTS = {}
def ident(name): return hashlib.sha256(('healthpig-native-v5/'+name).encode()).hexdigest()[:24].upper()
def obj(object_name, isa, **values):
    key=ident(object_name); OBJECTS[key]={'isa':isa,**values}; return key

def serialize(value, depth=0):
    pad='\t'*depth
    if isinstance(value,dict): return '{\n'+''.join('\t'*(depth+1)+json.dumps(k)+' = '+serialize(v,depth+1)+';\n' for k,v in value.items())+pad+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(depth+1)+serialize(v,depth+1)+',\n' for v in value)+pad+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value,ensure_ascii=False)

def configs(name, settings):
    refs=[]
    for mode in ['Debug','Release']:
        values=dict(settings)
        values|={'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'}
        if mode=='Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        refs.append(obj(name+mode,'XCBuildConfiguration',buildSettings=values,name=mode))
    return obj(name+'configlist','XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

file_refs={}
shared=sorted(ROOT.glob('Sources/Shared/*.swift'))
watch=sorted(ROOT.glob('Sources/Watch/*.swift'))
phone=sorted(ROOT.glob('Sources/Phone/*.swift'))
resources=sorted(ROOT.glob('Resources/*.json'))+[ROOT/'Resources/PigAssets.xcassets']
for p in shared+watch+phone+resources:
    rel=p.relative_to(ROOT).as_posix()
    kind='sourcecode.swift' if p.suffix=='.swift' else 'folder.assetcatalog' if p.suffix=='.xcassets' else 'text.json'
    file_refs[rel]=obj('file:'+rel,'PBXFileReference',lastKnownFileType=kind,path=rel,sourceTree='<group>')
products={platform:obj(platform+'product','PBXFileReference',explicitFileType='wrapper.application',path='HealthPig'+platform+'.app',sourceTree='BUILT_PRODUCTS_DIR') for platform in ['Watch','Phone']}
common={'SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','MARKETING_VERSION':'0.7.0','CURRENT_PROJECT_VERSION':'7','GENERATE_INFOPLIST_FILE':'YES','ENABLE_PREVIEWS':'YES','PRODUCT_NAME':'$(TARGET_NAME)','SWIFT_EMIT_LOC_STRINGS':'YES','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS':'NO','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
for platform, sources in [('Watch',shared+watch),('Phone',shared+phone)]:
    builds=[obj(platform+'build:'+p.relative_to(ROOT).as_posix(),'PBXBuildFile',fileRef=file_refs[p.relative_to(ROOT).as_posix()]) for p in sources]
    res=[obj(platform+'resource:'+p.name,'PBXBuildFile',fileRef=file_refs[p.relative_to(ROOT).as_posix()]) for p in resources]
    phases=[obj(platform+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0),obj(platform+'resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=res,runOnlyForDeploymentPostprocessing=0),obj(platform+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)]
    deps=[]
    settings=common|{'INFOPLIST_FILE':platform+'-Info.plist','CODE_SIGN_ENTITLEMENTS':platform+'.entitlements'}
    if platform=='Watch':
        settings|={'SDKROOT':'watchos','SUPPORTED_PLATFORMS':'watchos watchsimulator','WATCHOS_DEPLOYMENT_TARGET':'10.0','TARGETED_DEVICE_FAMILY':'4','PRODUCT_BUNDLE_IDENTIFIER':'org.example.HealthPig.Native.watchkitapp','SKIP_INSTALL':'YES'}
    else:
        settings|={'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1,2','PRODUCT_BUNDLE_IDENTIFIER':'org.example.HealthPig.Native','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO'}
        embed=obj('embedWatch','PBXBuildFile',fileRef=products['Watch'],settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
        phases.append(obj('copyWatch','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='$(CONTENTS_FOLDER_PATH)/Watch',dstSubfolderSpec=16,files=[embed],name='Embed Watch Content',runOnlyForDeploymentPostprocessing=0))
        proxy=obj('watchProxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=ident('Watchtarget'),remoteInfo='HealthPigWatch')
        deps=[obj('watchDependency','PBXTargetDependency',target=ident('Watchtarget'),targetProxy=proxy)]
    obj(platform+'target','PBXNativeTarget',buildConfigurationList=configs(platform,settings),buildPhases=phases,buildRules=[],dependencies=deps,name='HealthPig'+platform,productName='HealthPig'+platform,productReference=products[platform],productType='com.apple.product-type.application')

test_products = []
for platform in ['Watch','Phone']:
    paths=sorted((ROOT/'UITests'/platform).glob('*.swift'))
    refs=[]; builds=[]
    for path in paths:
        rel=path.relative_to(ROOT).as_posix()
        ref=obj('file:'+rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>')
        refs.append(ref); builds.append(obj('testbuild:'+rel,'PBXBuildFile',fileRef=ref))
    obj(platform+'uitestgroup','PBXGroup',children=refs,name=platform+' UI Tests',sourceTree='<group>')
    product=obj(platform+'uitestproduct','PBXFileReference',explicitFileType='wrapper.cfbundle',path='HealthPig'+platform+'UITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
    test_products.append(product)
    phases=[obj(platform+'uitestsources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0),obj(platform+'uitestframeworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)]
    proxy=obj(platform+'appTestProxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=ident(platform+'target'),remoteInfo='HealthPig'+platform)
    dependency=obj(platform+'appTestDependency','PBXTargetDependency',target=ident(platform+'target'),targetProxy=proxy)
    settings={'SWIFT_VERSION':'5.0','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'org.example.HealthPig.Native.'+platform+'UITests','TEST_TARGET_NAME':'HealthPig'+platform,'ENABLE_TESTING_SEARCH_PATHS':'YES'}
    if platform=='Watch': settings|={'SDKROOT':'watchos','WATCHOS_DEPLOYMENT_TARGET':'10.0','TARGETED_DEVICE_FAMILY':'4'}
    else: settings|={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1,2'}
    obj(platform+'uitesttarget','PBXNativeTarget',buildConfigurationList=configs(platform+'UITests',settings),buildPhases=phases,buildRules=[],dependencies=[dependency],name='HealthPig'+platform+'UITests',productName='HealthPig'+platform+'UITests',productReference=product,productType='com.apple.product-type.bundle.ui-testing')

groups=[]
for label,files in [('Shared',shared),('Watch',watch),('Phone',phone),('Resources',resources)]:
    groups.append(obj(label+'group','PBXGroup',children=[file_refs[p.relative_to(ROOT).as_posix()] for p in files],name=label,sourceTree='<group>'))
product_group=obj('productGroup','PBXGroup',children=list(products.values())+test_products,name='Products',sourceTree='<group>')
main=obj('mainGroup','PBXGroup',children=groups+[ident('Watchuitestgroup'),ident('Phoneuitestgroup'),product_group],sourceTree='<group>')
project_config=configs('Project',{'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_VERSION':'5.0','GCC_C_LANGUAGE_STANDARD':'gnu17','SWIFT_STRICT_CONCURRENCY':'targeted'})
obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2700'},buildConfigurationList=project_config,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=main,productRefGroup=product_group,projectDirPath='',projectRoot='',targets=[ident('Phonetarget'),ident('Watchtarget'),ident('Phoneuitesttarget'),ident('Watchuitesttarget')])
project=ROOT/'HealthPigNative.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':OBJECTS,'rootObject':ident('project')})+'\n')
schemes=project/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
for platform in ['Watch','Phone']:
    name='HealthPig'+platform
    ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(platform+"target")}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:HealthPigNative.xcodeproj"/>'
    test_ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(platform+"uitesttarget")}" BuildableName="{name}UITests.xctest" BlueprintName="{name}UITests" ReferencedContainer="container:HealthPigNative.xcodeproj"/>'
    xml=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    (schemes/(name+'.xcscheme')).write_text(xml+'\n')
print('Generated',project,'with Watch and Phone targets')
