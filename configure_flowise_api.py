"""
Configure Flowise API Key
-------------------------
Interactive script to set the Flowise API key in flowise-proxy-service-py/.env

Author: Enoch Sit
License: MIT
"""

import os
import sys
import re
from pathlib import Path
from datetime import datetime
import shutil


class ColorPrinter:
    """Helper class for colored console output"""
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

    @staticmethod
    def print_header(text):
        print(f"\n{ColorPrinter.HEADER}{ColorPrinter.BOLD}{text}{ColorPrinter.ENDC}")

    @staticmethod
    def print_success(text):
        print(f"{ColorPrinter.OKGREEN}✓ {text}{ColorPrinter.ENDC}")

    @staticmethod
    def print_warning(text):
        print(f"{ColorPrinter.WARNING}⚠ {text}{ColorPrinter.ENDC}")

    @staticmethod
    def print_error(text):
        print(f"{ColorPrinter.FAIL}✗ {text}{ColorPrinter.ENDC}")

    @staticmethod
    def print_info(text):
        print(f"{ColorPrinter.OKCYAN}ℹ {text}{ColorPrinter.ENDC}")


class FlowiseAPIConfigurator:
    def __init__(self, base_dir):
        self.base_dir = Path(base_dir)
        self.flowise_proxy_env = self.base_dir / "flowise-proxy-service-py" / ".env"
        
    def backup_env_file(self):
        """Create a backup of the .env file"""
        if self.flowise_proxy_env.exists():
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_path = self.flowise_proxy_env.with_suffix(f'.env.backup.{timestamp}')
            shutil.copy2(self.flowise_proxy_env, backup_path)
            ColorPrinter.print_info(f"Backup created: {backup_path.name}")
            return True
        return False
    
    def validate_api_key(self, api_key):
        """Validate the API key format"""
        if not api_key or not api_key.strip():
            return False, "API key cannot be empty"
        
        api_key = api_key.strip()
        
        # Check minimum length
        if len(api_key) < 20:
            return False, "API key seems too short (expected at least 20 characters)"
        
        # Check if it looks like a valid key (alphanumeric with possible special chars)
        if not re.match(r'^[A-Za-z0-9\-_]+$', api_key):
            ColorPrinter.print_warning("API key contains unusual characters. Proceeding anyway...")
        
        return True, api_key
    
    def update_flowise_api_key(self, api_key):
        """Update FLOWISE_API_KEY in flowise-proxy-service-py/.env"""
        if not self.flowise_proxy_env.exists():
            ColorPrinter.print_error(f".env file not found: {self.flowise_proxy_env}")
            ColorPrinter.print_info("Please run setup_env_files.bat first")
            return False
        
        # Create backup
        self.backup_env_file()
        
        # Read the current content
        with open(self.flowise_proxy_env, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Update FLOWISE_API_KEY
        pattern = r'FLOWISE_API_KEY=.*'
        replacement = f'FLOWISE_API_KEY={api_key}'
        
        if re.search(pattern, content):
            new_content = re.sub(pattern, replacement, content)
            updated = True
        else:
            # If FLOWISE_API_KEY doesn't exist, add it
            ColorPrinter.print_warning("FLOWISE_API_KEY not found in .env, adding it...")
            new_content = content.rstrip() + f'\n\n# Flowise API Key (added by configure_flowise_api.py)\nFLOWISE_API_KEY={api_key}\n'
            updated = True
        
        if updated:
            # Write back
            with open(self.flowise_proxy_env, 'w', encoding='utf-8') as f:
                f.write(new_content)
            
            return True
        
        return False
    
    def get_api_key_from_user(self):
        """Prompt user for API key with validation"""
        ColorPrinter.print_header("Flowise API Key Configuration")
        print("\nThis script will configure the Flowise API key in flowise-proxy-service-py/.env")
        print("\n" + "="*70)
        ColorPrinter.print_info("How to get your Flowise API key:")
        print("  1. Make sure Flowise is running (cd flowise && start-with-postgres.bat)")
        print("  2. Open http://localhost:3002 in your browser")
        print("  3. Go to Settings (gear icon)")
        print("  4. Navigate to 'API Keys' section")
        print("  5. Click 'Create New Key'")
        print("  6. Copy the generated key")
        print("="*70 + "\n")
        
        while True:
            try:
                api_key = input(f"{ColorPrinter.BOLD}Enter Flowise API Key (or 'q' to quit): {ColorPrinter.ENDC}").strip()
                
                if api_key.lower() == 'q':
                    ColorPrinter.print_warning("Configuration cancelled by user")
                    return None
                
                is_valid, result = self.validate_api_key(api_key)
                
                if is_valid:
                    return result
                else:
                    ColorPrinter.print_error(result)
                    retry = input("Try again? (y/n): ").strip().lower()
                    if retry != 'y':
                        return None
            
            except KeyboardInterrupt:
                print("\n")
                ColorPrinter.print_warning("Configuration cancelled by user")
                return None
            except Exception as e:
                ColorPrinter.print_error(f"Error reading input: {e}")
                return None


def main():
    """Main function"""
    try:
        # Get the base directory (where the script is located)
        base_dir = Path(__file__).parent.resolve()
        
        # Create configurator
        configurator = FlowiseAPIConfigurator(base_dir)
        
        # Get API key from user
        api_key = configurator.get_api_key_from_user()
        
        if not api_key:
            print("\nNo changes made.")
            return 1
        
        # Update the .env file
        ColorPrinter.print_header("\nUpdating Configuration...")
        
        if configurator.update_flowise_api_key(api_key):
            ColorPrinter.print_success(f"FLOWISE_API_KEY updated in {configurator.flowise_proxy_env.name}")
            
            # Show summary
            print("\n" + "="*70)
            ColorPrinter.print_header("Configuration Complete!")
            print("="*70)
            ColorPrinter.print_success("Flowise API key has been configured")
            
            print("\n" + ColorPrinter.BOLD + "Next Steps:" + ColorPrinter.ENDC)
            print("  1. Restart flowise-proxy-service-py:")
            print("     cd flowise-proxy-service-py")
            print("     docker compose down")
            print("     docker compose up -d")
            print("\n  2. Verify the service is working:")
            print("     docker logs flowise-proxy --tail=50")
            print("="*70)
            
            return 0
        else:
            ColorPrinter.print_error("Failed to update configuration")
            return 1
    
    except Exception as e:
        ColorPrinter.print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
