"""
ChatProxy Platform - Automated Drive Configuration and Path Updater

This script:
1. Detects available drives (C:, D:, etc.)
2. Checks for RAID configuration
3. Recommends optimal storage configuration
4. Updates docker-compose.yml and .env files to use recommended drives
5. Creates backups before making changes
6. Supports dry-run mode to preview changes

Author: Enoch Sit
License: MIT
"""

import os
import sys
import shutil
import subprocess
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional
import json

# Check for required packages
try:
    from ruamel.yaml import YAML
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=2, offset=0)
except ImportError:
    print("Installing required package: ruamel.yaml...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "ruamel.yaml"])
    from ruamel.yaml import YAML
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=2, offset=0)


class Colors:
    """ANSI color codes for terminal output"""
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    RED = '\033[31m'
    BLUE = '\033[36m'
    BOLD = '\033[1m'
    RESET = '\033[0m'


class DriveDetector:
    """Detects available drives and RAID configuration"""
    
    def __init__(self):
        self.drives = {}
        self.raid_detected = False
        self.raid_info = []
    
    def detect_drives(self) -> Dict[str, Dict]:
        """Detect all available drives and their properties"""
        print(f"\n{Colors.BLUE}[STEP 1/6] Detecting available drives...{Colors.RESET}")
        
        for letter in 'CDEFGHIJKLMNOPQRSTUVWXYZ':
            drive = f"{letter}:\\"
            if os.path.exists(drive):
                try:
                    stat = os.statvfs(drive) if hasattr(os, 'statvfs') else None
                    if stat:
                        total = stat.f_blocks * stat.f_frsize
                        free = stat.f_bavail * stat.f_frsize
                    else:
                        # Windows fallback
                        total, used, free = shutil.disk_usage(drive)
                    
                    free_gb = free / (1024**3)
                    total_gb = total / (1024**3)
                    
                    self.drives[letter] = {
                        'path': drive,
                        'free_gb': free_gb,
                        'total_gb': total_gb,
                        'exists': True
                    }
                    
                    print(f"{Colors.GREEN}[✓]{Colors.RESET} {letter}: drive - {free_gb:.1f} GB free / {total_gb:.1f} GB total")
                except Exception as e:
                    print(f"{Colors.YELLOW}[!]{Colors.RESET} {letter}: drive detected but couldn't read stats: {e}")
        
        return self.drives
    
    def check_raid(self) -> bool:
        """Check for RAID configuration"""
        print(f"\n{Colors.BLUE}[STEP 2/6] Checking RAID configuration...{Colors.RESET}")
        
        raid_keywords = ['RAID', 'PERC', 'LSI', 'Adaptec', 'MegaRAID', 'HP Smart Array']
        
        try:
            # Check WMIC for disk drives
            result = subprocess.run(
                ['wmic', 'diskdrive', 'get', 'Model,DeviceID'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    for keyword in raid_keywords:
                        if keyword.lower() in line.lower():
                            self.raid_detected = True
                            self.raid_info.append(line.strip())
                            print(f"{Colors.GREEN}[✓]{Colors.RESET} RAID detected: {line.strip()}")
        except Exception as e:
            print(f"{Colors.YELLOW}[!]{Colors.RESET} Could not check WMIC: {e}")
        
        try:
            # Check Storage Spaces (Windows Software RAID)
            result = subprocess.run(
                ['powershell', '-Command', 
                 'Get-StoragePool -IsPrimordial $false -ErrorAction SilentlyContinue | Select-Object FriendlyName'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0 and result.stdout.strip():
                lines = [l.strip() for l in result.stdout.split('\n') if l.strip() and 'FriendlyName' not in l]
                if lines:
                    self.raid_detected = True
                    self.raid_info.extend(lines)
                    print(f"{Colors.GREEN}[✓]{Colors.RESET} Windows Storage Spaces detected")
        except Exception as e:
            print(f"{Colors.YELLOW}[!]{Colors.RESET} Could not check Storage Spaces: {e}")
        
        if not self.raid_detected:
            print(f"{Colors.YELLOW}[i]{Colors.RESET} No RAID detected (may require admin privileges)")
        
        return self.raid_detected
    
    def get_recommendation(self) -> Tuple[str, str]:
        """
        Returns recommended drive configuration
        Returns: (data_drive_letter, reason)
        """
        print(f"\n{Colors.BLUE}[STEP 3/6] Analyzing optimal configuration...{Colors.RESET}")
        
        # If D: exists with RAID, strongly recommend D:
        if 'D' in self.drives and self.raid_detected:
            reason = "D: drive with RAID detected - optimal for data storage"
            print(f"{Colors.GREEN}[✓]{Colors.RESET} Recommendation: Use D: drive (RAID + good capacity)")
            return 'D', reason
        
        # If D: exists with >50GB, recommend D:
        if 'D' in self.drives and self.drives['D']['free_gb'] > 50:
            reason = "D: drive has good capacity (>50GB) - recommended for data storage"
            print(f"{Colors.GREEN}[✓]{Colors.RESET} Recommendation: Use D: drive (good capacity)")
            return 'D', reason
        
        # Otherwise use C:
        reason = "Using C: drive (single drive configuration)"
        print(f"{Colors.YELLOW}[!]{Colors.RESET} Recommendation: Use C: drive (no suitable D: drive)")
        
        if 'C' in self.drives and self.drives['C']['free_gb'] < 50:
            print(f"{Colors.RED}[⚠]{Colors.RESET} Warning: Limited space on C: drive ({self.drives['C']['free_gb']:.1f} GB)")
        
        return 'C', reason


class PathUpdater:
    """Updates docker-compose.yml and .env files with new paths"""
    
    def __init__(self, workspace_root: str, target_drive: str, dry_run: bool = True):
        self.workspace_root = Path(workspace_root)
        self.target_drive = target_drive
        self.dry_run = dry_run
        self.backup_dir = None
        self.changes = []
        self.yaml = YAML()
        self.yaml.preserve_quotes = True
        self.yaml.indent(mapping=2, sequence=2, offset=0)
    
    def create_backup(self):
        """Create backup of all configuration files"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.backup_dir = self.workspace_root / f"config_backup_{timestamp}"
        
        if not self.dry_run:
            self.backup_dir.mkdir(exist_ok=True)
            print(f"{Colors.GREEN}[✓]{Colors.RESET} Backup directory created: {self.backup_dir}")
    
    def backup_file(self, file_path: Path):
        """Backup a single file"""
        if self.dry_run:
            return
        
        relative_path = file_path.relative_to(self.workspace_root)
        backup_path = self.backup_dir / relative_path
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file_path, backup_path)
    
    def update_docker_compose(self, file_path: Path) -> bool:
        """Update volume paths in docker-compose.yml file"""
        if not file_path.exists():
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = self.yaml.load(f)
            
            if not data or 'services' not in data:
                return False
            
            modified = False
            changes_in_file = []
            
            # Define volume mappings based on service
            volume_mappings = {
                'mongodb-auth': f'{self.target_drive}:/DockerVolumes/mongodb-auth:/data/db',
                'mongodb': f'{self.target_drive}:/DockerVolumes/mongodb-proxy:/data/db',
                'postgres-accounting': f'{self.target_drive}:/DockerVolumes/postgres-accounting:/var/lib/postgresql/data',
                'flowise-postgres': f'{self.target_drive}:/DockerVolumes/flowise-postgres:/var/lib/postgresql/data',
            }
            
            for service_name, service_config in data['services'].items():
                if 'volumes' in service_config:
                    volumes = service_config['volumes']
                    
                    for i, volume in enumerate(volumes):
                        if isinstance(volume, str):
                            # Check if this is a data volume we should update
                            for key, new_path in volume_mappings.items():
                                if key in service_name.lower():
                                    # Extract the container path (after the :)
                                    parts = volume.split(':')
                                    if len(parts) >= 2:
                                        container_path = ':'.join(parts[1:])
                                        new_volume = new_path
                                        
                                        if volume != new_volume:
                                            old_volume = volume
                                            volumes[i] = new_volume
                                            modified = True
                                            changes_in_file.append(f"  {service_name}: {old_volume} → {new_volume}")
            
            if modified:
                self.backup_file(file_path)
                
                if not self.dry_run:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        self.yaml.dump(data, f)
                
                change_entry = {
                    'file': str(file_path.relative_to(self.workspace_root)),
                    'type': 'docker-compose',
                    'changes': changes_in_file
                }
                self.changes.append(change_entry)
                
                return True
            
        except Exception as e:
            print(f"{Colors.RED}[✗]{Colors.RESET} Error updating {file_path}: {e}")
            return False
        
        return False
    
    def update_env_file(self, file_path: Path) -> bool:
        """Update paths in .env file"""
        if not file_path.exists():
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            modified = False
            changes_in_file = []
            new_lines = []
            
            # Paths to update
            path_updates = {
                'FILE_STORAGE_PATH': f'{self.target_drive}:/ChatProxyData/uploads',
                'LOG_PATH': f'{self.target_drive}:/ChatProxyData/logs',
            }
            
            # Track which variables we found
            found_vars = set()
            
            for line in lines:
                original_line = line
                modified_line = False
                
                for var_name, new_path in path_updates.items():
                    if line.startswith(f'{var_name}='):
                        found_vars.add(var_name)
                        old_value = line.split('=', 1)[1].strip()
                        
                        # Only update if it's different
                        if old_value != new_path:
                            line = f'{var_name}={new_path}\n'
                            modified = True
                            modified_line = True
                            changes_in_file.append(f"  {var_name}: {old_value} → {new_path}")
                
                new_lines.append(line)
            
            # Add missing variables at the end
            for var_name, new_path in path_updates.items():
                if var_name not in found_vars:
                    new_lines.append(f'\n# Added by drive configuration script\n')
                    new_lines.append(f'{var_name}={new_path}\n')
                    modified = True
                    changes_in_file.append(f"  {var_name}: (added) → {new_path}")
            
            if modified:
                self.backup_file(file_path)
                
                if not self.dry_run:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.writelines(new_lines)
                
                change_entry = {
                    'file': str(file_path.relative_to(self.workspace_root)),
                    'type': 'env',
                    'changes': changes_in_file
                }
                self.changes.append(change_entry)
                
                return True
            
        except Exception as e:
            print(f"{Colors.RED}[✗]{Colors.RESET} Error updating {file_path}: {e}")
            return False
        
        return False
    
    def find_and_update_files(self):
        """Find and update all relevant configuration files"""
        print(f"\n{Colors.BLUE}[STEP 4/6] Scanning for configuration files...{Colors.RESET}")
        
        # Find docker-compose files
        docker_compose_files = [
            self.workspace_root / 'auth-service' / 'docker-compose.dev.yml',
            self.workspace_root / 'accounting-service' / 'docker-compose.yml',
            self.workspace_root / 'flowise' / 'docker-compose.yml',
            self.workspace_root / 'flowise-proxy-service-py' / 'docker-compose.yml',
        ]
        
        # Find .env files
        env_files = [
            self.workspace_root / 'flowise-proxy-service-py' / '.env',
        ]
        
        print(f"Found {len([f for f in docker_compose_files if f.exists()])} docker-compose files")
        print(f"Found {len([f for f in env_files if f.exists()])} .env files")
        
        print(f"\n{Colors.BLUE}[STEP 5/6] {'[DRY-RUN] Analyzing' if self.dry_run else 'Updating'} configuration files...{Colors.RESET}")
        
        # Update docker-compose files
        for file_path in docker_compose_files:
            if file_path.exists():
                if self.update_docker_compose(file_path):
                    mode = "[DRY-RUN]" if self.dry_run else "[✓]"
                    print(f"{Colors.GREEN}{mode}{Colors.RESET} Updated: {file_path.relative_to(self.workspace_root)}")
        
        # Update .env files
        for file_path in env_files:
            if file_path.exists():
                if self.update_env_file(file_path):
                    mode = "[DRY-RUN]" if self.dry_run else "[✓]"
                    print(f"{Colors.GREEN}{mode}{Colors.RESET} Updated: {file_path.relative_to(self.workspace_root)}")
    
    def show_summary(self):
        """Show summary of changes"""
        print(f"\n{Colors.BLUE}[STEP 6/6] Summary of Changes{Colors.RESET}")
        print("=" * 70)
        
        if not self.changes:
            print(f"{Colors.YELLOW}No changes needed - paths already configured correctly{Colors.RESET}")
            return
        
        for change in self.changes:
            print(f"\n{Colors.BOLD}{change['file']}{Colors.RESET} ({change['type']})")
            for detail in change['changes']:
                print(detail)
        
        print("\n" + "=" * 70)
        print(f"Total files modified: {len(self.changes)}")
        
        if not self.dry_run and self.backup_dir:
            print(f"{Colors.GREEN}[✓]{Colors.RESET} Backups saved to: {self.backup_dir}")
    
    def create_directory_structure(self):
        """Create the directory structure on target drive"""
        print(f"\n{Colors.BLUE}Creating directory structure on {self.target_drive}:{Colors.RESET}")
        
        directories = [
            f'{self.target_drive}:/DockerVolumes/mongodb-auth',
            f'{self.target_drive}:/DockerVolumes/mongodb-proxy',
            f'{self.target_drive}:/DockerVolumes/postgres-accounting',
            f'{self.target_drive}:/DockerVolumes/flowise-postgres',
            f'{self.target_drive}:/ChatProxyData/uploads',
            f'{self.target_drive}:/ChatProxyData/logs',
            f'{self.target_drive}:/ChatProxyData/backups',
        ]
        
        for directory in directories:
            dir_path = Path(directory)
            if not self.dry_run:
                try:
                    dir_path.mkdir(parents=True, exist_ok=True)
                    print(f"{Colors.GREEN}[✓]{Colors.RESET} Created: {directory}")
                except Exception as e:
                    print(f"{Colors.RED}[✗]{Colors.RESET} Failed to create {directory}: {e}")
            else:
                print(f"{Colors.BLUE}[DRY-RUN]{Colors.RESET} Would create: {directory}")


def main():
    print(f"""
{Colors.BOLD}╔════════════════════════════════════════════════════════════════╗
║   ChatProxy Platform - Drive Configuration & Path Updater     ║
║   Automated RAID detection and path optimization              ║
╚════════════════════════════════════════════════════════════════╝{Colors.RESET}
""")
    
    # Get workspace root
    workspace_root = Path(__file__).parent.resolve()
    print(f"Workspace: {workspace_root}")
    
    # Step 1: Detect drives
    detector = DriveDetector()
    drives = detector.detect_drives()
    
    if not drives:
        print(f"{Colors.RED}[✗]{Colors.RESET} No drives detected!")
        return 1
    
    # Step 2: Check RAID
    detector.check_raid()
    
    # Step 3: Get recommendation
    target_drive, reason = detector.get_recommendation()
    
    print(f"\n{Colors.BOLD}Recommended Configuration:{Colors.RESET}")
    print(f"  Data Storage: {Colors.GREEN}{target_drive}:{Colors.RESET} drive")
    print(f"  Reason: {reason}")
    
    if detector.raid_detected:
        print(f"  {Colors.GREEN}[RAID]{Colors.RESET} Data protection and performance benefits")
    
    # Ask user for confirmation
    print(f"\n{Colors.YELLOW}Options:{Colors.RESET}")
    print("  [1] Preview changes (dry-run)")
    print("  [2] Apply changes immediately")
    print("  [3] Cancel")
    
    choice = input("\nEnter your choice (1-3): ").strip()
    
    if choice == '3':
        print("Operation cancelled.")
        return 0
    
    dry_run = (choice == '1')
    
    # Step 4: Update paths
    updater = PathUpdater(workspace_root, target_drive, dry_run=dry_run)
    updater.create_backup()
    
    # Create directory structure
    updater.create_directory_structure()
    
    # Update files
    updater.find_and_update_files()
    
    # Show summary
    updater.show_summary()
    
    if dry_run:
        print(f"\n{Colors.YELLOW}This was a DRY-RUN. No files were modified.{Colors.RESET}")
        print(f"Run the script again and choose option [2] to apply changes.")
    else:
        print(f"\n{Colors.GREEN}✓ Configuration updated successfully!{Colors.RESET}")
        print(f"\n{Colors.BOLD}Next Steps:{Colors.RESET}")
        print("  1. Review the changes above")
        print("  2. Restart all Docker services:")
        print("     cd flowise && stop.bat && start-with-postgres.bat")
        print("     cd ..\\auth-service && stop.bat && start.bat")
        print("     cd ..\\accounting-service && stop.bat && start.bat")
        print("     cd ..\\flowise-proxy-service-py && docker-compose down && docker-compose up -d")
        print("     cd ..\\bridge && stop.bat && start.bat")
        print("  3. Run: check_system.bat")
    
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Operation cancelled by user.{Colors.RESET}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.RED}[✗] Unexpected error: {e}{Colors.RESET}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
