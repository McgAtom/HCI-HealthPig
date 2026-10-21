#!/usr/bin/env python3
"""Build, pair, install and launch the native apps on local simulators; never target physical devices."""
from pathlib import Path
import argparse
import json
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
DERIVED = Path(tempfile.gettempdir()) / 'healthpig-native-demo-build'

def run(*args):
    print('+', ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), check=True)

def read(*args):
    return json.loads(subprocess.check_output(list(map(str, args)), text=True))

def simulator(platform, name, device_type):
    runtimes = [r for r in read('xcrun', 'simctl', 'list', 'runtimes', '-j')['runtimes']
                if r['isAvailable'] and r['name'].startswith(platform + ' ')]
    if not runtimes:
        raise SystemExit(f'{platform}运行时尚未安装。在Xcode组件设置安装，或执行 xcodebuild -downloadPlatform {platform} -architectureVariant arm64。')
    runtime = max(runtimes, key=lambda r: tuple(int(x) for x in r['version'].split('.')))
    devices = read('xcrun', 'simctl', 'list', 'devices', 'available', '-j')['devices'].get(runtime['identifier'], [])
    matching = [d for d in devices if d['name'] == name and d['deviceTypeIdentifier'] == device_type]
    if matching:
        return matching[0]['udid']
    return subprocess.check_output(['xcrun', 'simctl', 'create', name, device_type, runtime['identifier']], text=True).strip()

def main():
    parser = argparse.ArgumentParser(description='Launch native apps on local simulators.')
    parser.add_argument('--reopen-only', action='store_true', help='Reopen installed apps without rebuilding or reinstalling.')
    options = parser.parse_args()
    watch = simulator('watchOS', 'HCI Watch 46mm', 'com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm')
    phone = simulator('iOS', 'HCI iPhone', 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro')
    pairs = list(read('xcrun', 'simctl', 'list', 'pairs', '-j')['pairs'].values())
    linked = any(p['watch']['udid'] == watch and p['phone']['udid'] == phone for p in pairs)
    if not linked:
        if any(p['watch']['udid'] == watch or p['phone']['udid'] == phone for p in pairs):
            raise SystemExit('HCI模拟器已与另一设备配对。请在Device Hub检查配对；脚本不会解除现有配对。')
        run('xcrun', 'simctl', 'pair', watch, phone)
    for uid in [phone, watch]:
        states = [d for group in read('xcrun', 'simctl', 'list', 'devices', '-j')['devices'].values() for d in group]
        if next(d['state'] for d in states if d['udid'] == uid) != 'Booted':
            run('xcrun', 'simctl', 'boot', uid)
        run('xcrun', 'simctl', 'bootstatus', uid, '-b')
    if not options.reopen_only:
        run('xcodebuild', '-project', ROOT/'HealthPigNative.xcodeproj', '-scheme', 'HealthPigPhone',
            '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={phone}',
            '-derivedDataPath', DERIVED, 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'build')
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    for app in [developer.parent/'Applications/DeviceHub.app', developer/'Applications/Simulator.app']:
        if app.exists():
            run('open', app)
            break
    for uid, folder, app, bundle in [
        (phone, 'Debug-iphonesimulator', 'HealthPigPhone', 'org.example.HealthPig.Native'),
        (watch, 'Debug-watchsimulator', 'HealthPigWatch', 'org.example.HealthPig.Native.watchkitapp')]:
        if not options.reopen_only:
            run('xcrun', 'simctl', 'install', uid, DERIVED/'Build/Products'/folder/(app+'.app'))
        run('xcrun', 'simctl', 'launch', '--terminate-running-process', uid, bundle)
    # A live PID can coexist with a black idle screen or a returned clock face.
    # Require visible homepage text before reporting the Watch app ready.
    screenshot = Path(tempfile.gettempdir())/'healthpig-watch-launch-check.png'
    for attempt in range(8):
        subprocess.run(['xcrun', 'simctl', 'io', watch, 'screenshot', str(screenshot)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        check = subprocess.run(['swift', str(ROOT/'tools/verify_watch_home.swift'), str(screenshot)],
                               capture_output=True, text=True)
        if check.returncode == 0:
            print(check.stdout.strip())
            break
        time.sleep(0.5)
    else:
        raise SystemExit('手表进程已启动，但首页不可见，未报告启动成功。请在Device Hub选择“HCI Watch 46mm”，唤醒屏幕后重试 --reopen-only。')
    print('\n两端已启动。Device Hub中选择“HCI iPhone”和“HCI Watch 46mm”查看。')
    print('脚本保留已有收藏；真实传感器采集请另行安排，模拟器可使用“公开样本演示”。')

if __name__ == '__main__':
    main()
