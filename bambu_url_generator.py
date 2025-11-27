#!/usr/bin/env python3
"""
Bambu Lab Cloud URL Generator (Standalone)
=========================================

Generates a complete bambu:/// URL for use with bambu_source, independent of any external library.

This tool logs into the Bambu Lab Cloud API (supporting both Global and China regions),
fetches camera credentials, and constructs the appropriate URL for remote video streaming.

It can be run interactively or non-interactively for use in scripts.
"""

import sys
import os
import argparse
import uuid
import json
from pathlib import Path
import requests
import getpass

# --- Constants ---
NET_VER = "02.03.01.52"
CLI_VER = "02.03.01.51"
CLI_ID = str(uuid.uuid4())

GLOBAL_API = "https://api.bambulab.com/v1"
CHINA_API = "https://api.bambulab.cn/v1"
TOKEN_FILE_PATH = "/config/.bambu_token"

# --- API Client ---

class BambuAPIError(Exception):
    """Custom exception for API errors."""
    pass

class SimpleBambuClient:
    """A standalone, simple client to interact with the Bambu Lab Cloud API."""

    def __init__(self, region: str = "global", token: str = None):
        self.region = region
        self.base_url = CHINA_API if region == "china" else GLOBAL_API
        self.token = token
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'BambuStudio/01.09.01.66',
            'Content-Type': 'application/json'
        })

    def _request(self, method, endpoint, **kwargs):
        """Internal request handler."""
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        if self.token:
            self.session.headers['Authorization'] = f"Bearer {self.token}"

        try:
            response = self.session.request(method, url, timeout=30, **kwargs)
            if response.status_code == 401:
                 raise BambuAPIError("AUTHORIZATION_FAILED (授权失败). Your token may be invalid or expired. Please --login again.")
            # Don't raise for status on login endpoint, as it uses 400 for flow control
            if "/user-service/user/login" not in url:
                response.raise_for_status()
            if not response.content:
                return None
            return response.json()
        except requests.exceptions.RequestException as e:
            raise BambuAPIError(f"Network error (网络错误): {e}")
        except json.JSONDecodeError:
            raise BambuAPIError(f"Invalid JSON response from server (服务器返回无效JSON): {response.text}")

    def login(self, username, password):
        """
        Handles the complete login flow, including 2FA verification code.
        """
        # Step 1: Initial login attempt with password
        payload = {"account": username, "password": password}
        try:
            data = self._request("POST", "user-service/user/login", json=payload)

            if data and data.get("loginType") == "verifyCode":
                # Step 2: Verification code is required
                print("Verification code required. (需要验证码)")
                return self._handle_email_verification(username)

            if data and data.get("accessToken"):
                self.token = data["accessToken"]
                return self.token

            error_msg = data.get("message", "Unknown login error from initial attempt")
            raise BambuAPIError(f"Login failed (登录失败): {error_msg}")

        except requests.exceptions.HTTPError as e:
             # Handle cases where the server returns an error on the initial attempt
            error_body = e.response.json()
            error_msg = error_body.get("message", "HTTP error during login")
            raise BambuAPIError(f"Login failed (登录失败): {error_msg}")
        except BambuAPIError as e:
            raise e

    def _handle_email_verification(self, account: str) -> str:
        """Handle email/phone verification code flow."""
        # Step 2a: Send the verification code
        is_china = self.region == "china"
        send_endpoint = "user-service/user/sendsmscode" if is_china else "user-service/user/sendemail/code"
        payload_key = "phone" if is_china else "email"
        send_payload = {payload_key: account, "type": "codeLogin"}
        
        print("Requesting verification code... (正在请求验证码...)")
        self._request("POST", send_endpoint, json=send_payload)
        
        # Step 2b: Get code from user
        prompt = "Enter the SMS code (请输入短信验证码): " if is_china else "Enter the email code (请输入邮箱验证码): "
        code = input(prompt)

        # Step 2c: Verify the code
        verify_payload = {"account": account, "code": code}
        verify_data = self._request("POST", "user-service/user/login", json=verify_payload)
        
        token = verify_data.get("accessToken")
        if token:
            self.token = token
            return token
        else:
            error_msg = verify_data.get("message", "Verification failed")
            raise BambuAPIError(error_msg)

    def get_devices(self):
        """Fetches a list of devices."""
        response = self._request("GET", "iot-service/api/user/bind")
        return response.get('devices', [])

    def get_camera_credentials(self, device_id):
        """Fetches camera credentials (ttcode)."""
        return self._request("POST", "iot-service/api/user/ttcode", json={'dev_id': device_id})

# --- Token Management ---

def save_token(region: str, token: str):
    """Saves the region and token to the token file."""
    try:
        with open(TOKEN_FILE_PATH, 'w') as f:
            json.dump({"region": region, "token": token}, f)
        os.chmod(TOKEN_FILE_PATH, 0o600)
    except IOError as e:
        print(f"⚠️ Warning: Could not save token to {TOKEN_FILE_PATH}: {e}", file=sys.stderr)

def load_token():
    """Loads region and token from the token file."""
    if not TOKEN_FILE_PATH.exists():
        return None, None
    try:
        with open(TOKEN_FILE_PATH, 'r') as f:
            data = json.load(f)
        return data.get("region"), data.get("token")
    except (IOError, json.JSONDecodeError) as e:
        print(f"⚠️ Warning: Could not load or parse token from {TOKEN_FILE_PATH}: {e}", file=sys.stderr)
        return None, None

# --- URL Generation ---

def get_full_url(client: SimpleBambuClient, device: dict, quiet: bool) -> str:
    """Fetches camera credentials and constructs the full URL."""
    device_id = device.get('dev_id')
    if not device_id:
        raise ValueError("Device dictionary is missing 'dev_id'")

    creds = client.get_camera_credentials(device_id)

    if not quiet:
        print("\n--- Full Camera Credentials Response ---", file=sys.stderr)
        print(json.dumps(creds, indent=2), file=sys.stderr)
        print("----------------------------------------\n", file=sys.stderr)

    tutk_uid = creds.get('ttcode')
    authkey = creds.get('authkey')
    passwd = creds.get('passwd')
    tutk_region = creds.get('region', 'us')
    dev_ver = device.get('ota_version', '00.00.00.00')

    if not all([tutk_uid, authkey, passwd]):
        raise ValueError(f"Incomplete camera credentials received: {creds}")

    params = {
        "uid": tutk_uid,
        "authkey": authkey,
        "passwd": passwd,
        "region": tutk_region,
        "device": device_id,
        "net_ver": NET_VER,
        "dev_ver": dev_ver,
        "refresh_url": "1",
        "cli_id": CLI_ID,
        "cli_ver": CLI_VER,
    }

    query_string = "&".join([f"{key}={value}" for key, value in params.items()])
    return f"bambu:///tutk?{query_string}"

# --- Main Logic ---

def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="Bambu Lab Cloud URL Generator (Standalone).",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "-s", "--serial",
        help="Printer serial number for non-interactive mode.\nPrints only the final URL to stdout.",
        type=str, default=None
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
        "--region",
        help="Specify the API region during login ('global' or 'china').\nOnly used with --login.",
        type=str, choices=['global', 'china'], default='global'
    )
    parser.add_argument(
       "--discover",
       help="List available printers in 'serial name' format for scripting.",
       action="store_true"
    )
    args = parser.parse_args()

    if args.login:
        print("Bambu Lab Interactive Login (Bambu Lab 交互式登录)")
        print(f"Target Region (目标区域): {args.region.upper()}")
        print("===================================================")
        try:
            prompt = "Enter your Bambu Lab phone number (输入您的手机号): " if args.region == 'china' else "Enter your Bambu Lab email (输入您的Bambu Lab邮箱): "
            username = input(prompt)
            password = getpass.getpass("Enter your password (输入您的密码): ")
            client = SimpleBambuClient(region=args.region)
            token = client.login(username, password)
            save_token(args.region, token)
            print("✅ Login successful! Token and region have been saved for future use.")
            print("   (登录成功! Token和区域已保存供将来使用)")
            return 0
        except BambuAPIError as e:
            print(f"❌ Login failed (登录失败): {e}", file=sys.stderr)
            return 1
        except (EOFError, KeyboardInterrupt):
            print("\nLogin cancelled. (登录已取消)", file=sys.stderr)
            return 1

    is_interactive = not args.serial and not args.quiet and not args.discover

    if is_interactive:
        print("Bambu Lab Cloud URL Generator (Bambu Lab 云端URL生成器)")
        print("======================================================")

    region, token = load_token()
    if not token:
        print("ERROR: NO_TOKEN_FOUND (未找到Token)", file=sys.stderr)
        print("Please run with '--login' to authenticate first.", file=sys.stderr)
        print("(请先使用 '--login' 参数运行以进行认证)", file=sys.stderr)
        return 1

    if is_interactive:
        print(f"✅ Authenticated using saved token for region '{region}'. (使用区域'{region}'的已保存Token进行认证)")

    client = SimpleBambuClient(region=region, token=token)
    try:
        devices = client.get_devices()
        if not devices:
            if not args.discover:
               print("❌ No printers found in your account. (您的账户下未找到任何打印机)", file=sys.stderr)
            return 0
    except BambuAPIError as e:
        print(f"❌ Failed to get devices (获取设备列表失败): {e}", file=sys.stderr)
        return 1

    if args.discover:
       for device in devices:
           name = device.get('name', 'Unknown')
           serial = device.get('dev_id', 'N/A')
           print(f"{serial} {name}")
       return 0

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
            online = device.get('online', False)
            status = "Online (在线)" if online else "Offline (离线)"
            print(f"{idx}. {name} ({model}) - {status}")

        if not devices:
             return 1
        if len(devices) > 1:
            try:
                choice = int(input(f"\nSelect a printer (选择一台打印机) (1-{len(devices)}): ")) - 1
                if not 0 <= choice < len(devices):
                    raise ValueError
            except (ValueError, EOFError, KeyboardInterrupt):
                print("❌ Invalid selection. (无效选择)", file=sys.stderr)
                return 1
        else:
            choice = 0
        selected_device = devices[choice]
    else:
        selected_device = next((d for d in devices if d.get('online')), devices)

    if is_interactive:
        print(f"\nSelected (已选择): {selected_device.get('name')}")
        print("Fetching camera credentials... (正在获取摄像头凭证...)")

    try:
        bambu_url = get_full_url(client, selected_device, args.quiet)
    except (BambuAPIError, ValueError) as e:
        print(f"❌ Failed to generate URL (生成URL失败): {e}", file=sys.stderr)
        return 1

    if is_interactive:
        print("\n" + "="*50)
        print("✅ Bambu Source URL Generated (Bambu Source URL已生成):")
        print(bambu_url)
        print("="*50)
        print("\nUse this URL with bambu_source or in your scripts. (请在bambu_source或您的脚本中使用此URL)")
    else:
        print(bambu_url)

    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        if sys.stdout.isatty():
            print("\nInterrupted by user. (用户中断)", file=sys.stderr)
        sys.exit(1)