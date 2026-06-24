import os
import shutil
import subprocess
import json

def run_comparison():
    # Paths
    root_dir = "C:/Users/chainoob/fyp_project/ml_backend"
    fhmm_path = os.path.join(root_dir, "services/fhmm_service.py")
    sigs_path = os.path.join(root_dir, "data/appliance_signatures.json")
    
    fhmm_bak = fhmm_path + ".bak"
    sigs_bak = sigs_path + ".bak"
    
    print("1. Backing up current modifications...")
    shutil.copyfile(fhmm_path, fhmm_bak)
    shutil.copyfile(sigs_path, sigs_bak)
    
    try:
        print("2. Restoring baseline versions from git...")
        # Use git checkout to revert these two files
        subprocess.run(["git", "checkout", "HEAD", "--", "services/fhmm_service.py", "data/appliance_signatures.json"], cwd=root_dir, check=True)
        
        print("3. Running baseline evaluation...")
        cmd_base = [
            "python", "evaluation/cross_dataset.py",
            "--consolidated-csv", "data/CLEAN_House1.csv",
            "--appliance-map", "Laptop=Appliance7",
            "--max-rows", "20000"
        ]
        res_base = subprocess.run(cmd_base, cwd=root_dir, capture_output=True, text=True)
        print("Baseline stdout:")
        print(res_base.stdout)
        
        # Parse baseline report JSON if printed or parse metrics manually
        print("4. Re-restoring modified versions...")
        shutil.copyfile(fhmm_bak, fhmm_path)
        shutil.copyfile(sigs_bak, sigs_path)
        
        print("5. Running improved evaluation...")
        res_impr = subprocess.run(cmd_base, cwd=root_dir, capture_output=True, text=True)
        print("Improved stdout:")
        print(res_impr.stdout)
        
    finally:
        # Clean up backups and ensure modifications are restored
        if os.path.exists(fhmm_bak):
            if not os.path.exists(fhmm_path) or os.path.getsize(fhmm_path) != os.path.getsize(fhmm_bak):
                shutil.copyfile(fhmm_bak, fhmm_path)
            os.remove(fhmm_bak)
        if os.path.exists(sigs_bak):
            if not os.path.exists(sigs_path) or os.path.getsize(sigs_path) != os.path.getsize(sigs_bak):
                shutil.copyfile(sigs_bak, sigs_path)
            os.remove(sigs_bak)

if __name__ == "__main__":
    run_comparison()
