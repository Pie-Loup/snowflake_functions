#!/usr/bin/env python3
"""
Script to convert JSON to a single line with escaped newlines
Usage: python3 json_escape.py <json_file>
"""
import json
import sys

def escape_json(filename):
    try:
        with open(filename, 'r') as f:
            data = json.load(f)
        
        # Convert to compact JSON string
        compact_json = json.dumps(data, separators=(',', ':'))
        
        # Escape newlines
        escaped_json = compact_json.replace('\\n', '\\\\n')
        
        print(escaped_json)
        
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in '{filename}': {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 json_escape.py <json_file>", file=sys.stderr)
        sys.exit(1)
    
    escape_json(sys.argv[1])