#!/usr/bin/env python3
"""
Simple DBML Generator
Chỉ tạo file DBML từ SQL schema, không tạo ERD

Usage:
    python generate_dbml.py [sql_file] [output_dir]
"""

import sys
import os
from pathlib import Path

# Import modules
from sql_parser import SQLParser
from dbml_generator import DBMLGenerator


def main():
    # Default values
    sql_file = '../sql/01_schema.sql'
    output_dir = './output'
    
    # Parse command line arguments
    if len(sys.argv) > 1:
        sql_file = sys.argv[1]
    if len(sys.argv) > 2:
        output_dir = sys.argv[2]
    
    print("🚀 DBML Generator - Chỉ tạo file DBML")
    print("=" * 40)
    
    # Tạo output directory
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    try:
        # Parse SQL schema
        print(f"📖 Đang parse schema: {sql_file}")
        parser = SQLParser()
        tables = parser.parse_sql_file(sql_file)
        
        if not tables:
            print("❌ Không tìm thấy bảng nào")
            return False
        
        print(f"✅ Đã parse {len(tables)} bảng")
        
        # Count total relationships found
        total_relationships = sum(len(table.foreign_keys) for table in tables.values())
        print(f"🔗 Tìm thấy {total_relationships} relationships tự động")
        
        # Generate DBML
        print("📝 Đang tạo DBML...")
        generator = DBMLGenerator()
        generator.load_tables(tables)
        
        # Basic DBML
        basic_dbml_path = os.path.join(output_dir, 'supermarket.dbml')
        generator.save_dbml(basic_dbml_path)
        print(f"✅ DBML cơ bản: {basic_dbml_path}")
        
        # Full DBML with groups  
        full_dbml_path = os.path.join(output_dir, 'supermarket_full.dbml')
        basic_dbml = generator.generate_dbml()
        groups_dbml = generator.generate_table_groups()
        full_dbml = f'{basic_dbml}\n\n// Table Groups\n{groups_dbml}'
        with open(full_dbml_path, 'w', encoding='utf-8') as f:
            f.write(full_dbml)
        print(f"✅ DBML đầy đủ: {full_dbml_path}")
        
        # JSON schema (optional)
        json_path = os.path.join(output_dir, 'parsed_schema.json')
        parser.save_json(json_path)
        print(f"✅ JSON schema: {json_path}")
        
        print("\n🎯 Upload file .dbml lên dbdiagram.io để xem ERD online!")
        return True
        
    except Exception as e:
        print(f"❌ Lỗi: {e}")
        return False


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
