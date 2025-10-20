#!/usr/bin/env python3
"""
Script to convert JSON to a single line with escaped newlines for Snowflake secrets.

This utility prepares Google Cloud service account JSON files for use as
Snowflake secrets by:
1. Compacting to a single line (no whitespace)
2. Escaping newlines in the private_key field (\\n -> \\\\n)

Usage:
    # From file
    python3 json_escape.py service_account.json
    
    # From stdin (piping)
    cat service_account.json | python3 json_escape.py -
    
    # Copy to clipboard (requires pyperclip)
    python3 json_escape.py service_account.json --clipboard
    python3 json_escape.py --clipboard < service_account.json
    
    # Alternative: pipe from stdin
    cat service_account.json | python3 json_escape.py
    
Examples:
    python3 json_escape.py my_credentials.json
    python3 json_escape.py my_credentials.json --clipboard
    cat credentials.json | python3 json_escape.py --clipboard
"""

import json
import sys
import argparse

def escape_json(json_string):
    """
    Convert JSON to compact format with escaped newlines.
    
    Args:
        json_string (str): Raw JSON string
        
    Returns:
        str: Compact JSON with escaped newlines
        
    Raises:
        json.JSONDecodeError: If JSON is invalid
    """
    # Parse JSON to validate and load as dict
    data = json.loads(json_string)
    
    # Convert to compact JSON string (no whitespace)
    compact_json = json.dumps(data, separators=(',', ':'))
    
    # Escape newlines (important for private_key field)
    # Single \ followed by n becomes double \\ followed by n
    escaped_json = compact_json.replace('\\n', '\\\\n')
    
    return escaped_json

def copy_to_clipboard(text):
    """
    Copy text to system clipboard.
    
    Args:
        text (str): Text to copy
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        import pyperclip
        pyperclip.copy(text)
        return True
    except ImportError:
        print("\n⚠️  Clipboard feature requires pyperclip package", file=sys.stderr)
        print("Install with: pip install pyperclip", file=sys.stderr)
        print("\nOutput printed below instead:\n", file=sys.stderr)
        return False
    except Exception as e:
        print(f"\n⚠️  Failed to copy to clipboard: {e}", file=sys.stderr)
        print("\nOutput printed below instead:\n", file=sys.stderr)
        return False

def main():
    parser = argparse.ArgumentParser(
        description='Escape JSON for Snowflake secrets (compact + escape newlines)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 json_escape.py credentials.json
  python3 json_escape.py credentials.json --clipboard
  cat credentials.json | python3 json_escape.py -
  python3 json_escape.py - --clipboard < credentials.json
        """
    )
    
    parser.add_argument(
        'filename',
        nargs='?',
        default=None,
        help='JSON file to process (use "-" or omit for stdin)'
    )
    
    parser.add_argument(
        '-c', '--clipboard',
        action='store_true',
        help='Copy result to clipboard instead of printing'
    )
    
    parser.add_argument(
        '--verify',
        action='store_true',
        help='Verify the escaped JSON can be parsed correctly'
    )
    
    args = parser.parse_args()
    
    try:
        # Determine input source
        if args.filename is None or args.filename == '-':
            # Read from stdin
            if sys.stdin.isatty() and args.filename is None:
                parser.print_help()
                sys.exit(1)
            json_string = sys.stdin.read()
            source = "stdin"
        else:
            # Read from file
            try:
                with open(args.filename, 'r') as f:
                    json_string = f.read()
                source = args.filename
            except FileNotFoundError:
                print(f"❌ Error: File '{args.filename}' not found", file=sys.stderr)
                sys.exit(1)
        
        # Process JSON
        escaped_json = escape_json(json_string)
        
        # Verify if requested
        if args.verify:
            try:
                # Try to parse the escaped version (simulating what Snowflake does)
                # Need to unescape for verification
                verify_json = escaped_json.replace('\\\\n', '\\n')
                json.loads(verify_json)
                print("✓ Verification successful: JSON is valid", file=sys.stderr)
            except json.JSONDecodeError as e:
                print(f"⚠️  Verification warning: {e}", file=sys.stderr)
        
        # Output result
        if args.clipboard:
            if copy_to_clipboard(escaped_json):
                print(f"✓ Copied to clipboard from {source}", file=sys.stderr)
                print("\nPaste this into your CREATE SECRET statement:", file=sys.stderr)
                print("CREATE OR REPLACE SECRET GSHEET_CREDENTIALS", file=sys.stderr)
                print("  TYPE = GENERIC_STRING", file=sys.stderr)
                print("  SECRET_STRING = '<paste here>';", file=sys.stderr)
            else:
                # Fallback to printing
                print(escaped_json)
        else:
            print(escaped_json)
            print(f"\n✓ Processed {source} successfully", file=sys.stderr)
            print("\nNext step: Copy the output above and use it in Snowflake:", file=sys.stderr)
            print("CREATE OR REPLACE SECRET GSHEET_CREDENTIALS", file=sys.stderr)
            print("  TYPE = GENERIC_STRING", file=sys.stderr)
            print("  SECRET_STRING = '<paste the output above>';", file=sys.stderr)
    
    except json.JSONDecodeError as e:
        print(f"❌ Error: Invalid JSON: {e}", file=sys.stderr)
        print("\nTip: Ensure your file is valid JSON", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(f"❌ Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()