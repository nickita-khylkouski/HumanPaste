import sys
import os

# Add HumanPaste/ to sys.path so `import typeguard` resolves to HumanPaste/typeguard/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
