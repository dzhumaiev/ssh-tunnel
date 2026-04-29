# 1. Store the path to your key
$key = "C:\Users\PATHTO\.ssh\id_rsa"

# 2. Give yourself ownership of the file
icacls $key /setowner $env:USERNAME

# 3. Disable inheritance (strips permissions from 'Everyone', 'SYSTEM', etc.)
icacls $key /inheritance:r

# 4. Grant ONLY yourself Full Control
icacls $key /grant:r "${env:USERNAME}:F"
