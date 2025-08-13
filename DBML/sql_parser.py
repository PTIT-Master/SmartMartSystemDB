"""
SQL Parser Module
Phân tích cú pháp SQL schema để trích xuất thông tin bảng, cột và quan hệ
"""

import re
import json
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict


@dataclass
class Column:
    """Thông tin cột"""
    name: str
    data_type: str
    is_primary_key: bool = False
    is_foreign_key: bool = False
    is_not_null: bool = False
    default_value: Optional[str] = None
    constraints: List[str] = None
    references_table: Optional[str] = None
    references_column: Optional[str] = None
    
    def __post_init__(self):
        if self.constraints is None:
            self.constraints = []


@dataclass
class ForeignKey:
    """Thông tin khóa ngoại"""
    column: str
    references_table: str
    references_column: str
    constraint_name: str


@dataclass
class Table:
    """Thông tin bảng"""
    name: str
    columns: List[Column]
    primary_keys: List[str]
    foreign_keys: List[ForeignKey]
    indexes: List[str] = None
    constraints: List[str] = None
    
    def __post_init__(self):
        if self.indexes is None:
            self.indexes = []
        if self.constraints is None:
            self.constraints = []


class SQLParser:
    """Parser cho PostgreSQL schema"""
    
    def __init__(self):
        self.tables: Dict[str, Table] = {}
        self.relationships: List[Dict] = []
    
    def parse_sql_file(self, file_path: str) -> Dict[str, Table]:
        """Parse file SQL và trả về dictionary các bảng"""
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        return self.parse_sql_content(content)
    
    def parse_sql_content(self, content: str) -> Dict[str, Table]:
        """Parse nội dung SQL"""
        # Loại bỏ comments
        content = self._remove_comments(content)
        
        # Tìm tất cả CREATE TABLE statements
        table_matches = re.finditer(
            r'CREATE\s+TABLE\s+(\w+)\s*\(\s*(.*?)\s*\);',
            content,
            re.DOTALL | re.IGNORECASE
        )
        
        for match in table_matches:
            table_name = match.group(1)
            table_definition = match.group(2)
            
            table = self._parse_table_definition(table_name, table_definition)
            self.tables[table_name] = table
        
        # Parse foreign key constraints
        self._parse_foreign_keys(content)
        
        # Parse indexes
        self._parse_indexes(content)
        
        return self.tables
    
    def _remove_comments(self, content: str) -> str:
        """Loại bỏ SQL comments"""
        # Loại bỏ single line comments
        content = re.sub(r'--.*$', '', content, flags=re.MULTILINE)
        # Loại bỏ multi-line comments
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        return content
    
    def _parse_table_definition(self, table_name: str, definition: str) -> Table:
        """Parse định nghĩa bảng"""
        columns = []
        primary_keys = []
        foreign_keys = []
        constraints = []
        
        # Normalize whitespace and clean up definition
        definition = re.sub(r'\s+', ' ', definition.strip())
        
        # First, extract all CONSTRAINT clauses (including multi-line ones)
        constraint_pattern = r'CONSTRAINT\s+(\w+)\s+(.*?)(?=,\s*CONSTRAINT|\s*$|,\s*\w+\s+\w+)'
        constraint_matches = re.finditer(constraint_pattern, definition, re.IGNORECASE | re.DOTALL)
        
        for constraint_match in constraint_matches:
            constraint_name = constraint_match.group(1)
            constraint_def = constraint_match.group(2).strip()
            
            # Check for foreign key
            fk_match = re.search(
                r'FOREIGN\s+KEY\s*\((\w+)\)\s+REFERENCES\s+(\w+)\s*\((\w+)\)',
                constraint_def,
                re.IGNORECASE
            )
            if fk_match:
                fk = ForeignKey(
                    column=fk_match.group(1),
                    references_table=fk_match.group(2),
                    references_column=fk_match.group(3),
                    constraint_name=constraint_name
                )
                foreign_keys.append(fk)
            else:
                constraints.append(f"CONSTRAINT {constraint_name} {constraint_def}")
        
        # Remove CONSTRAINT clauses from definition for column parsing
        definition_without_constraints = re.sub(
            r'CONSTRAINT\s+\w+\s+.*?(?=,\s*CONSTRAINT|,\s*\w+\s+\w+|\s*$)',
            '',
            definition,
            flags=re.IGNORECASE | re.DOTALL
        )
        
        # Parse columns from remaining definition
        # Split by comma, but be careful with functions and constraints
        column_parts = self._smart_split_columns(definition_without_constraints)
        
        for part in column_parts:
            part = part.strip()
            if not part or part.upper().startswith('CONSTRAINT'):
                continue
                
            # Parse column definition
            column = self._parse_column_definition(part)
            if column:
                columns.append(column)
                if column.is_primary_key:
                    primary_keys.append(column.name)
        
        return Table(
            name=table_name,
            columns=columns,
            primary_keys=primary_keys,
            foreign_keys=foreign_keys,
            constraints=constraints
        )
    
    def _smart_split_columns(self, definition: str) -> List[str]:
        """Smart split columns, xử lý trường hợp có parentheses trong function calls"""
        parts = []
        current_part = ""
        paren_level = 0
        
        for char in definition:
            if char == '(':
                paren_level += 1
            elif char == ')':
                paren_level -= 1
            elif char == ',' and paren_level == 0:
                if current_part.strip():
                    parts.append(current_part.strip())
                current_part = ""
                continue
            
            current_part += char
        
        # Add the last part
        if current_part.strip():
            parts.append(current_part.strip())
        
        return parts
    
    def _parse_column_definition(self, line: str) -> Optional[Column]:
        """Parse định nghĩa cột"""
        # Basic column pattern
        column_match = re.match(
            r'(\w+)\s+([A-Z_]+(?:\([^)]+\))?)',
            line,
            re.IGNORECASE
        )
        
        if not column_match:
            return None
        
        column_name = column_match.group(1)
        data_type = column_match.group(2)
        
        # Check for constraints
        is_primary_key = 'PRIMARY KEY' in line.upper()
        is_not_null = 'NOT NULL' in line.upper()
        
        # Extract default value
        default_match = re.search(r'DEFAULT\s+([^,\s]+)', line, re.IGNORECASE)
        default_value = default_match.group(1) if default_match else None
        
        # Extract constraints
        constraints = []
        if 'UNIQUE' in line.upper():
            constraints.append('UNIQUE')
        
        check_match = re.search(r'CHECK\s*\([^)]+\)', line, re.IGNORECASE)
        if check_match:
            constraints.append(check_match.group(0))
        
        return Column(
            name=column_name,
            data_type=data_type,
            is_primary_key=is_primary_key,
            is_not_null=is_not_null,
            default_value=default_value,
            constraints=constraints
        )
    
    def _parse_foreign_keys(self, content: str):
        """Parse các foreign key constraints"""
        # Update foreign key info in columns
        for table in self.tables.values():
            for fk in table.foreign_keys:
                # Find the column and update its foreign key info
                for column in table.columns:
                    if column.name == fk.column:
                        column.is_foreign_key = True
                        column.references_table = fk.references_table
                        column.references_column = fk.references_column
                        break
    
    def _parse_indexes(self, content: str):
        """Parse index definitions"""
        index_matches = re.finditer(
            r'CREATE\s+INDEX\s+(\w+)\s+ON\s+(\w+)\s*\(([^)]+)\)',
            content,
            re.IGNORECASE
        )
        
        for match in index_matches:
            index_name = match.group(1)
            table_name = match.group(2)
            column_list = match.group(3).strip()
            
            if table_name in self.tables:
                # Store column names for DBML, not index name
                self.tables[table_name].indexes.append(column_list)
    
    def get_relationships(self) -> List[Dict]:
        """Lấy danh sách các mối quan hệ giữa các bảng"""
        relationships = []
        
        for table in self.tables.values():
            for fk in table.foreign_keys:
                relationship = {
                    'from_table': table.name,
                    'from_column': fk.column,
                    'to_table': fk.references_table,
                    'to_column': fk.references_column,
                    'constraint_name': fk.constraint_name
                }
                relationships.append(relationship)
        
        return relationships
    
    def to_json(self) -> str:
        """Export dữ liệu thành JSON"""
        data = {
            'tables': {name: asdict(table) for name, table in self.tables.items()},
            'relationships': self.get_relationships()
        }
        return json.dumps(data, indent=2, ensure_ascii=False)
    
    def save_json(self, file_path: str):
        """Lưu dữ liệu thành file JSON"""
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(self.to_json())


if __name__ == "__main__":
    # Test parser
    parser = SQLParser()
    tables = parser.parse_sql_file('../sql/01_schema.sql')
    
    print(f"Đã parse {len(tables)} bảng:")
    for table_name in tables:
        print(f"- {table_name}")
    
    # Save to JSON
    parser.save_json('parsed_schema.json')
    print("Đã lưu kết quả vào parsed_schema.json")
