#!/usr/bin/env python3
"""
Bambu Lab Cloud URL Generator
=============================

Generates a complete bambu:/// URL for use with bambu_source, independent of Bambu Studio.

This tool logs into the Bambu Lab Cloud API, fetches camera credentials,
and constructs the appropriate URL for remote video streaming.

It can be run interactively or non-interactively for use in scripts.
"""

import sys
import os
import argparse
import uuid
from pathlib import Path

# The script is now located within the package, so direct imports work.
try:
    from bambulab import BambuAuthenticator, BambuClient, BambuAPIError
except ImportError:
    print("ERROR: The 'Bambu-Lab-Cloud-API' library is required. (需要 'Bambu-Lab-Cloud-API' 库)", file=sys.stderr)
    print("Please ensure it is installed and accessible. (请确保已安装并可访问)", file=sys.stderr)
    sys.exit(1)

# These values seem to be client-specific and are hardcoded based on a working example
# from Bambu Studio. They may need updating if future versions of bambu_source
# require different values.
NET_VER = "02.03.01.52"
CLI_VER = "02.03.01.51"
CLI_ID = str(uuid.uuid4())

def get_full_url(client: BambuClient, device: dict, quiet: bool) -> str:
    """Fetches camera credentials and constructs the full URL."""
    device_id = device.get('dev_id')
    if not device_id:
        raise ValueError("Device dictionary is missing 'dev_id'")

    creds = client.get_camera_credentials(device_id)

    # --- Print the full credentials response if not in quiet/discover mode ---
    if not quiet:
        import json
        print("\n--- Full Camera Credentials Response ---", file=sys.stderr)
        print(json.dumps(creds, indent=2), file=sys.stderr)
        print("----------------------------------------\n", file=sys.stderr)


    # --- Extract all necessary parameters ---
    tutk_uid = creds.get('ttcode')
    authkey = creds.get('authkey')
    passwd = creds.get('passwd')
    region = creds.get('region', 'us')  # Default to 'us' if not provided
    dev_ver = device.get('ota_version', '00.00.00.00')  # Fallback if not found

    if not all([tutk_uid, authkey, passwd]):
        raise ValueError(f"Incomplete camera credentials received: {creds}")

    # --- Construct the full URL with all parameters ---
    params = {
        "uid": tutk_uid,
        "authkey": authkey,
        "passwd": passwd,
        "region": region,
        "device": device_id,
        "net_ver": NET_VER,
        "dev_ver": dev_ver,
        "refresh_url": "1",
        "cli_id": CLI_ID,
        "cli_ver": CLI_VER,
    }
    
    query_string = "&".join([f"{key}={value}" for key, value in params.items()])
    return f"bambu:///tutk?{query_string}"

def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="Bambu Lab Cloud URL Generator.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "-s", "--serial",
        help="Printer serial number for non-interactive mode.\nPrints only the final URL to stdout.",
        type=str,
        default=None
    )
    parser.add_argument(
        "-q", "--quiet",
        help="Suppress all informational output (implies non-interactive).\nPrints only the URL for the first available printer if --serial is not used.",
        action="store_true"
    )
    parser.add_argument(
        "--login",
        help="Run interactive login to create or refresh the API token.",
        action="store_true"
    )
    parser.add_argument(
       "--discover",
       help="List available printers in 'serial name' format for scripting.",
       action="store_true"
    )
    args = parser.parse_args()

    auth = BambuAuthenticator()

    # --- 1. Handle Interactive Login ---
    if args.login:
        print("Bambu Lab Interactive Login (Bambu Lab 交互式登录)")
        print("===================================================")
        try:
            import getpass
            username = input("Enter your Bambu Lab email (输入您的Bambu Lab邮箱): ")
            password = getpass.getpass("Enter your password (输入您的密码): ")
            token = auth.login(username, password)
            print("✅ Login successful! Token has been saved for future use. (登录成功! Token已保存供将来使用)")
            return 0
        except BambuAPIError as e:
            print(f"❌ Login failed (登录失败): {e}", file=sys.stderr)
            return 1
        except (EOFError, KeyboardInterrupt):
            print("\nLogin cancelled. (登录已取消)", file=sys.stderr)
            return 1

    # In discover mode, it should always be non-interactive
    is_interactive = not args.serial and not args.quiet and not args.discover

    # Only print titles in full interactive mode
    if is_interactive:
        print("Bambu Lab Cloud URL Generator (Bambu Lab 云端URL生成器)")
        print("======================================================")

    # --- 2. Authentication (using saved token) ---
    try:
        token = auth.get_or_create_token()
        # Only print status in full interactive mode
        if is_interactive:
            print("✅ Authenticated using saved token. (使用已保存的Token进行认证)")
    except BambuAPIError as e:
       # Custom error handling for scripting
       if "No valid saved token found" in str(e):
           print("ERROR: NO_TOKEN_FOUND (未找到Token)", file=sys.stderr)
       else:
           print(f"ERROR: AUTH_FAILED (认证失败): {e}", file=sys.stderr)
       return 1

    # --- 3. Get Devices ---
    client = BambuClient(token=token)
    try:
        devices = client.get_devices()
        if not devices:
            # For discover, printing nothing is a valid empty list.
            if not args.discover:
               print("❌ No printers found in your account. (您的账户下未找到任何打印机)", file=sys.stderr)
            return 0 # Exit cleanly with no output if no devices found
    except BambuAPIError as e:
        print(f"❌ Failed to get devices (获取设备列表失败): {e}", file=sys.stderr)
        return 1

    # --- Handle Discovery Mode ---
    if args.discover:
       for device in devices:
           name = device.get('name', 'Unknown')
           serial = device.get('dev_id', 'N/A')
           print(f"{serial} {name}")
       return 0

    # --- 4. Select Device ---
    selected_device = None
    if args.serial:
        selected_device = next((d for d in devices if d.get('dev_id') == args.serial), None)
        if not selected_device:
            print(f"❌ Printer with serial '{args.serial}' not found. (未找到序列号为 '{args.serial}' 的打印机)", file=sys.stderr)
            return 1
    elif is_interactive:
        print("\nAvailable printers (可用打印机):")
        for idx, device in enumerate(devices, 1):
            name = device.get('name', 'Unknown')
            model = device.get('dev_product_name', 'Unknown')
            serial = device.get('dev_id', 'N/A')
            online = device.get('online', False)
            status = "Online (在线)" if online else "Offline (离线)"
            print(f"{idx}. {name} ({model}) - {status}")
            print(f"   Serial (序列号): {serial}")

        if len(devices) > 1:
            try:
                choice = int(input(f"\nSelect a printer (选择一台打印机) (1-{len(devices)}): ")) - 1
                if not 0 <= choice < len(devices):
                    raise ValueError
            except (ValueError, EOFError):
                print("❌ Invalid selection. (无效选择)", file=sys.stderr)
                return 1
        else:
            choice = 0
        selected_device = devices[choice]
    else:
        # Quiet mode with no serial, just pick the first online printer or the very first one
        selected_device = next((d for d in devices if d.get('online')), devices[0])

    if is_interactive:
        print(f"\nSelected (已选择): {selected_device.get('name')}")
        print("Fetching camera credentials... (正在获取摄像头凭证...)")

    # --- 5. Get URL ---
    try:
        bambu_url = get_full_url(client, selected_device, args.quiet or args.discover)
    except (BambuAPIError, ValueError) as e:
        print(f"❌ Failed to generate URL (生成URL失败): {e}", file=sys.stderr)
        return 1

    # --- 6. Output ---
    if is_interactive:
        print("\n" + "="*50)
        print("✅ Bambu Source URL Generated (Bambu Source URL已生成):")
        print(bambu_url)
        print("="*50)
        print("\nUse this URL with bambu_source or in your scripts. (请在bambu_source或您的脚本中使用此URL)")
    else:
        # In non-interactive or quiet mode, print only the URL to stdout
        print(bambu_url)

    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        # Avoid printing a messy stack trace on Ctrl+C
        if sys.stdout.isatty():
            print("\nInterrupted by user. (用户中断)", file=sys.stderr)
        sys.exit(1)