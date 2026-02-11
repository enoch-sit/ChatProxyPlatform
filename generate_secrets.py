"""
Generate and populate ALL secrets for ChatProxy Platform services.
Automatically updates .env files with secure secrets across all services.

Author: Enoch Sit
License: MIT
"""

import os
import secrets
import string
import re
from pathlib import Path
from typing import Dict, List, Tuple


class SecretGenerator:
    """Generate cryptographically secure secrets for JWT and database passwords."""
    
    @staticmethod
    def generate_jwt_secret(length: int = 64) -> str:
        """
        Generate a secure JWT secret using cryptographically strong random.
        Avoids shell-special characters that break Docker Compose ($, &, %, {, }, |, etc.)
        
        Args:
            length: Length of the secret (default 64 characters)
            
        Returns:
            Secure random string suitable for JWT signing
        """
        # Safe characters: no $, &, %, {, }, |, `, ", ', \, etc.
        alphabet = string.ascii_letters + string.digits + "!@#*()-_=+[].:,<>?"
        return ''.join(secrets.choice(alphabet) for _ in range(length))
    
    @staticmethod
    def generate_password(length: int = 32) -> str:
        """
        Generate a secure database password.
        Avoids shell-special characters that break Docker Compose ($, &, %, etc.)
        
        Args:
            length: Length of the password (default 32 characters)
            
        Returns:
            Secure random password safe for Docker Compose
        """
        # Safe characters: no $, &, %, {, }, |, `, ", ', \, etc.
        alphabet = string.ascii_letters + string.digits + "!@#*-_=+"
        return ''.join(secrets.choice(alphabet) for _ in range(length))


class EnvFileUpdater:
    """Update .env files with generated secrets."""
    
    def __init__(self, workspace_root: Path):
        self.workspace_root = workspace_root
        
        # Services requiring JWT secrets (must be identical)
        self.jwt_services = [
            "auth-service",
            "accounting-service",
            "flowise-proxy-service-py"
        ]
        
        # PostgreSQL databases
        self.postgres_services = [
            ("flowise", "POSTGRES_PASSWORD"),
            ("flowise", "DATABASE_PASSWORD"),  # Also update DATABASE_PASSWORD
            ("accounting-service", "POSTGRES_PASSWORD"),
            ("accounting-service", "DB_PASSWORD")  # Also update DB_PASSWORD
        ]
        
        # MongoDB databases
        self.mongo_services = [
            ("auth-service", "MONGO_INITDB_ROOT_PASSWORD")
        ]
        
        # Flowise specific secrets
        self.flowise_secrets = [
            ("flowise", "FLOWISE_SECRETKEY_OVERWRITE")
            # NOTE: FLOWISE_API_KEY must be created AFTER Flowise is running
            # through the Flowise UI, then manually added to flowise-proxy .env
        ]
        
        # Additional JWT secrets for flowise-proxy
        self.additional_jwt_secrets = [
            ("flowise-proxy-service-py", "JWT_SECRET_KEY")
        ]
        
    def read_env_file(self, service: str) -> Tuple[List[str], Dict[str, str]]:
        """
        Read .env file and parse existing variables.
        
        Args:
            service: Service name (e.g., 'auth-service')
            
        Returns:
            Tuple of (lines, variables_dict)
        """
        env_path = self.workspace_root / service / ".env"
        
        if not env_path.exists():
            raise FileNotFoundError(f".env file not found: {env_path}")
        
        with open(env_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        variables = {}
        for line in lines:
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                variables[key.strip()] = value.strip()
        
        return lines, variables
    
    def write_env_file(self, service: str, lines: List[str]):
        """
        Write updated lines to .env file with backup.
        
        Args:
            service: Service name
            lines: Updated lines to write
        """
        env_path = self.workspace_root / service / ".env"
        backup_path = self.workspace_root / service / ".env.backup"
        
        # Create backup
        if env_path.exists():
            with open(env_path, 'r', encoding='utf-8') as f:
                backup_content = f.read()
            with open(backup_path, 'w', encoding='utf-8') as f:
                f.write(backup_content)
        
        # Write updated content
        with open(env_path, 'w', encoding='utf-8') as f:
            f.writelines(lines)
    
    def update_jwt_secrets(self, access_secret: str, refresh_secret: str) -> Dict[str, bool]:
        """
        Update JWT secrets in all three services with the same values.
        
        Args:
            access_secret: JWT access token secret
            refresh_secret: JWT refresh token secret
            
        Returns:
            Dict mapping service names to success status
        """
        results = {}
        
        for service in self.jwt_services:
            try:
                lines, variables = self.read_env_file(service)
                
                # Update lines
                updated_lines = []
                access_updated = False
                refresh_updated = False
                
                for line in lines:
                    stripped = line.strip()
                    
                    # Update JWT_ACCESS_SECRET
                    if stripped.startswith('JWT_ACCESS_SECRET='):
                        updated_lines.append(f'JWT_ACCESS_SECRET={access_secret}\n')
                        access_updated = True
                    # Update JWT_REFRESH_SECRET
                    elif stripped.startswith('JWT_REFRESH_SECRET='):
                        updated_lines.append(f'JWT_REFRESH_SECRET={refresh_secret}\n')
                        refresh_updated = True
                    else:
                        updated_lines.append(line)
                
                # Append if not found
                if not access_updated:
                    updated_lines.append(f'\n# Generated JWT Secrets\nJWT_ACCESS_SECRET={access_secret}\n')
                if not refresh_updated:
                    updated_lines.append(f'JWT_REFRESH_SECRET={refresh_secret}\n')
                
                # Write back
                self.write_env_file(service, updated_lines)
                results[service] = True
                
            except Exception as e:
                print(f"❌ Error updating {service}: {e}")
                results[service] = False
        
        return results
    
    def update_database_passwords(self, postgres_password: str, mongo_password: str) -> Dict[str, bool]:
        """
        Update database passwords in services.
        
        Args:
            postgres_password: PostgreSQL password
            mongo_password: MongoDB password
            
        Returns:
            Dict mapping service names to success status
        """
        results = {}
        
        # Update PostgreSQL passwords
        for service, var_name in self.postgres_services:
            try:
                lines, variables = self.read_env_file(service)
                
                # Update lines
                updated_lines = []
                password_updated = False
                
                for line in lines:
                    stripped = line.strip()
                    
                    if stripped.startswith(f'{var_name}='):
                        updated_lines.append(f'{var_name}={postgres_password}\n')
                        password_updated = True
                    else:
                        updated_lines.append(line)
                
                # Append if not found
                if not password_updated:
                    updated_lines.append(f'\n# Generated PostgreSQL Password\n{var_name}={postgres_password}\n')
                
                # Write back
                self.write_env_file(service, updated_lines)
                results[f"{service} ({var_name})"] = True
                
            except Exception as e:
                print(f"❌ Error updating {service} PostgreSQL password: {e}")
                results[f"{service} ({var_name})"] = False
        
        # Update MongoDB passwords
        for service, var_name in self.mongo_services:
            try:
                lines, variables = self.read_env_file(service)
                
                # Update lines
                updated_lines = []
                password_updated = False
                
                for line in lines:
                    stripped = line.strip()
                    
                    if stripped.startswith(f'{var_name}='):
                        updated_lines.append(f'{var_name}={mongo_password}\n')
                        password_updated = True
                    else:
                        updated_lines.append(line)
                
                # Append if not found (MongoDB password might not exist in template)
                if not password_updated:
                    updated_lines.append(f'\n# Generated MongoDB Password\n{var_name}={mongo_password}\n')
                
                # Write back
                self.write_env_file(service, updated_lines)
                results[f"{service} (MongoDB)"] = True
                
            except Exception as e:
                print(f"❌ Error updating {service} MongoDB password: {e}")
                results[f"{service} (MongoDB)"] = False
        
        return results
    
    def update_flowise_secrets(self, flowise_secret_key: str, flowise_api_key: str) -> Dict[str, bool]:
        """
        Update Flowise-specific secrets.
        
        Args:
            flowise_secret_key: Flowise encryption key
            flowise_api_key: Flowise API key
            
        Returns:
            Dict mapping service names to success status
        """
        results = {}
        
        for service, var_name in self.flowise_secrets:
            try:
                lines, variables = self.read_env_file(service)
                
                # Determine which secret to use
                secret_value = flowise_secret_key if var_name == "FLOWISE_SECRETKEY_OVERWRITE" else flowise_api_key
                
                # Update lines
                updated_lines = []
                secret_updated = False
                
                for line in lines:
                    stripped = line.strip()
                    
                    # Handle commented out variables
                    if stripped.startswith(f'# {var_name}=') or stripped.startswith(f'#{var_name}='):
                        # Uncomment and set value
                        updated_lines.append(f'{var_name}={secret_value}\n')
                        secret_updated = True
                    elif stripped.startswith(f'{var_name}='):
                        updated_lines.append(f'{var_name}={secret_value}\n')
                        secret_updated = True
                    else:
                        updated_lines.append(line)
                
                # Append if not found
                if not secret_updated:
                    updated_lines.append(f'\n# Generated Flowise Secret\n{var_name}={secret_value}\n')
                
                # Write back
                self.write_env_file(service, updated_lines)
                results[f"{service} ({var_name})"] = True
                
            except Exception as e:
                print(f"❌ Error updating {service} {var_name}: {e}")
                results[f"{service} ({var_name})"] = False
        
        return results
    
    def update_additional_jwt_secrets(self, jwt_secret: str) -> Dict[str, bool]:
        """
        Update additional JWT secrets (JWT_SECRET_KEY for flowise-proxy).
        
        Args:
            jwt_secret: JWT secret key
            
        Returns:
            Dict mapping service names to success status
        """
        results = {}
        
        for service, var_name in self.additional_jwt_secrets:
            try:
                lines, variables = self.read_env_file(service)
                
                # Update lines
                updated_lines = []
                secret_updated = False
                
                for line in lines:
                    stripped = line.strip()
                    
                    if stripped.startswith(f'{var_name}='):
                        updated_lines.append(f'{var_name}={jwt_secret}\n')
                        secret_updated = True
                    else:
                        updated_lines.append(line)
                
                # Append if not found
                if not secret_updated:
                    updated_lines.append(f'\n# Generated JWT Secret Key\n{var_name}={jwt_secret}\n')
                
                # Write back
                self.write_env_file(service, updated_lines)
                results[f"{service} ({var_name})"] = True
                
            except Exception as e:
                print(f"❌ Error updating {service} {var_name}: {e}")
                results[f"{service} ({var_name})"] = False
        
        return results
    
    def update_mongodb_connection_string(self, mongo_password: str) -> Dict[str, bool]:
        """
        Update MongoDB connection strings with password.
        
        Args:
            mongo_password: MongoDB password
            
        Returns:
            Dict mapping service names to success status
        """
        results = {}
        
        try:
            service = "flowise-proxy-service-py"
            lines, variables = self.read_env_file(service)
            
            # Update lines
            updated_lines = []
            url_updated = False
            
            for line in lines:
                stripped = line.strip()
                
                if stripped.startswith('MONGODB_URL='):
                    # Replace password in connection string
                    new_url = f'MONGODB_URL=mongodb://admin:{mongo_password}@mongodb-proxy:27017/flowise_proxy?authSource=admin\n'
                    updated_lines.append(new_url)
                    url_updated = True
                else:
                    updated_lines.append(line)
            
            # Append if not found
            if not url_updated:
                updated_lines.append(f'\n# Generated MongoDB Connection String\nMONGODB_URL=mongodb://admin:{mongo_password}@mongodb-proxy:27017/flowise_proxy?authSource=admin\n')
            
            # Write back
            self.write_env_file(service, updated_lines)
            results[f"{service} (MONGODB_URL)"] = True
            
        except Exception as e:
            print(f"❌ Error updating MongoDB connection string: {e}")
            results[f"{service} (MONGODB_URL)"] = False
        
        return results


class ColorPrinter:
    """Print colored console output for Windows."""
    
    # ANSI color codes (work in Windows Terminal and modern cmd)
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    BOLD = '\033[1m'
    RESET = '\033[0m'
    
    @classmethod
    def print_header(cls, text: str):
        """Print a colored header."""
        print(f"\n{cls.BOLD}{cls.CYAN}{'═' * 70}{cls.RESET}")
        print(f"{cls.BOLD}{cls.CYAN}{text}{cls.RESET}")
        print(f"{cls.BOLD}{cls.CYAN}{'═' * 70}{cls.RESET}\n")
    
    @classmethod
    def print_success(cls, text: str):
        """Print success message."""
        print(f"{cls.GREEN}✓ {text}{cls.RESET}")
    
    @classmethod
    def print_warning(cls, text: str):
        """Print warning message."""
        print(f"{cls.YELLOW}⚠ {text}{cls.RESET}")
    
    @classmethod
    def print_error(cls, text: str):
        """Print error message."""
        print(f"{cls.RED}✗ {text}{cls.RESET}")
    
    @classmethod
    def print_info(cls, text: str):
        """Print info message."""
        print(f"{cls.BLUE}ℹ {text}{cls.RESET}")


def main():
    """Main execution function."""
    printer = ColorPrinter()
    
    # Print header
    printer.print_header("ChatProxy Platform - Comprehensive Secret Generator")
    
    # Get workspace root
    workspace_root = Path(__file__).parent
    printer.print_info(f"Workspace: {workspace_root}")
    
    # Check if .env files exist
    printer.print_info("Checking for .env files...")
    services = ["auth-service", "accounting-service", "flowise-proxy-service-py", "flowise"]
    missing_files = []
    
    for service in services:
        env_path = workspace_root / service / ".env"
        if env_path.exists():
            printer.print_success(f"{service}/.env found")
        else:
            printer.print_error(f"{service}/.env NOT FOUND")
            missing_files.append(service)
    
    if missing_files:
        print()
        printer.print_error("Missing .env files! Run setup_env_files.bat first.")
        printer.print_info("Command: setup_env_files.bat")
        return 1
    
    # Generate secrets
    print()
    printer.print_info("Generating cryptographically secure secrets...")
    
    generator = SecretGenerator()
    
    # JWT secrets (must be identical across services)
    jwt_access_secret = generator.generate_jwt_secret(64)
    jwt_refresh_secret = generator.generate_jwt_secret(64)
    jwt_secret_key = generator.generate_jwt_secret(64)  # For flowise-proxy JWT_SECRET_KEY
    
    # Database passwords
    postgres_password = generator.generate_password(32)
    mongo_password = generator.generate_password(32)
    
    # Flowise secrets
    flowise_secret_key = generator.generate_jwt_secret(64)  # Encryption key
    
    printer.print_success(f"JWT_ACCESS_SECRET: {jwt_access_secret[:20]}... (64 chars)")
    printer.print_success(f"JWT_REFRESH_SECRET: {jwt_refresh_secret[:20]}... (64 chars)")
    printer.print_success(f"JWT_SECRET_KEY: {jwt_secret_key[:20]}... (64 chars)")
    printer.print_success(f"POSTGRES_PASSWORD: {postgres_password[:16]}... (32 chars)")
    printer.print_success(f"MONGO_PASSWORD: {mongo_password[:16]}... (32 chars)")
    printer.print_success(f"FLOWISE_SECRETKEY: {flowise_secret_key[:20]}... (64 chars)")
    printer.print_warning("FLOWISE_API_KEY: Must be created AFTER Flowise starts (see docs)")
    
    # Update JWT secrets
    print()
    printer.print_info("Updating .env files with JWT secrets...")
    
    updater = EnvFileUpdater(workspace_root)
    jwt_results = updater.update_jwt_secrets(jwt_access_secret, jwt_refresh_secret)
    
    # Print JWT results
    print()
    for service, success in jwt_results.items():
        if success:
            printer.print_success(f"{service}/.env updated with JWT secrets")
        else:
            printer.print_error(f"{service}/.env JWT update FAILED")
    
    # Update database passwords
    print()
    printer.print_info("Updating database passwords...")
    
    db_results = updater.update_database_passwords(postgres_password, mongo_password)
    
    # Print database results
    print()
    for service, success in db_results.items():
        if success:
            printer.print_success(f"{service} password updated")
        else:
            printer.print_error(f"{service} password update FAILED")
    
    # Update MongoDB connection string
    print()
    printer.print_info("Updating MongoDB connection strings...")
    
    mongo_url_results = updater.update_mongodb_connection_string(mongo_password)
    
    # Print MongoDB URL results
    print()
    for service, success in mongo_url_results.items():
        if success:
            printer.print_success(f"{service} updated")
        else:
            printer.print_error(f"{service} update FAILED")
    
    # Update Flowise secrets
    print()
    printer.print_info("Updating Flowise encryption key...")
    
    flowise_results = updater.update_flowise_secrets(flowise_secret_key, "")
    
    # Print Flowise results
    print()
    for service, success in flowise_results.items():
        if success:
            printer.print_success(f"{service} updated")
        else:
            printer.print_error(f"{service} update FAILED")
    
    # Update additional JWT secrets
    print()
    printer.print_info("Updating additional JWT secrets...")
    
    additional_jwt_results = updater.update_additional_jwt_secrets(jwt_secret_key)
    
    # Print additional JWT results
    print()
    for service, success in additional_jwt_results.items():
        if success:
            printer.print_success(f"{service} updated")
        else:
            printer.print_error(f"{service} update FAILED")
    
    # Summary
    print()
    printer.print_header("Summary")
    
    all_results = {**jwt_results, **db_results, **mongo_url_results, **flowise_results, **additional_jwt_results}
    success_count = sum(1 for success in all_results.values() if success)
    total_count = len(all_results)
    
    if success_count == total_count:
        printer.print_success(f"All {success_count} updates completed successfully!")
        print()
        printer.print_success("✓ JWT secrets (JWT_ACCESS_SECRET, JWT_REFRESH_SECRET)")
        printer.print_success("  → auth-service, accounting-service, flowise-proxy")
        printer.print_success("✓ Additional JWT secret (JWT_SECRET_KEY)")
        printer.print_success("  → flowise-proxy")
        printer.print_success("✓ PostgreSQL passwords (POSTGRES_PASSWORD, DB_PASSWORD, DATABASE_PASSWORD)")
        printer.print_success("  → flowise, accounting-service")
        printer.print_success("✓ MongoDB passwords (MONGO_INITDB_ROOT_PASSWORD)")
        printer.print_success("  → auth-service")
        printer.print_success("✓ MongoDB connection string (MONGODB_URL)")
        printer.print_success("  → flowise-proxy")
        printer.print_success("✓ Flowise encryption key (FLOWISE_SECRETKEY_OVERWRITE)")
        printer.print_success("  → flowise")
        print()
        printer.print_warning("⚠ MANUAL STEP REQUIRED:")
        printer.print_warning("  After starting Flowise, create API key in UI:")
        printer.print_warning("  1. Start Flowise: cd flowise && start-with-postgres.bat")
        printer.print_warning("  2. Open http://localhost:3002")
        printer.print_warning("  3. Go to Settings → API Keys → Create New Key")
        printer.print_warning("  4. Copy the key to flowise-proxy-service-py/.env")
        printer.print_warning("     FLOWISE_API_KEY=<your-generated-key>")
        print()
        printer.print_info("Backups created: <service>/.env.backup")
        printer.print_info("Next step: Start services with docker compose")
        return 0
    else:
        printer.print_warning(f"Updated {success_count}/{total_count} configurations")
        printer.print_error("Some updates failed. Check errors above.")
        return 1


if __name__ == "__main__":
    try:
        exit_code = main()
        exit(exit_code)
    except KeyboardInterrupt:
        print("\n\nOperation cancelled by user.")
        exit(130)
    except Exception as e:
        ColorPrinter.print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
