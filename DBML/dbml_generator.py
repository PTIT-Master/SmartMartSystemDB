"""
DBML Generator Module
Tạo file DBML (Database Markup Language) từ cấu trúc dữ liệu đã parse
"""

from typing import Dict, List
from sql_parser import Table, Column, ForeignKey


class DBMLGenerator:
    """Generator để tạo DBML từ schema đã parse"""
    
    def __init__(self):
        self.tables: Dict[str, Table] = {}
        self.project_name = "Supermarket Database"
        self.note = "Hệ thống quản lý siêu thị bán lẻ"
    
    def load_tables(self, tables: Dict[str, Table]):
        """Load tables từ parser"""
        self.tables = tables
    
    def generate_dbml(self) -> str:
        """Tạo nội dung DBML"""
        dbml_content = []
        
        # Project header
        dbml_content.append(f'Project "{self.project_name}" {{')
        dbml_content.append(f'  database_type: "PostgreSQL"')
        dbml_content.append(f'  Note: "{self.note}"')
        dbml_content.append('}')
        dbml_content.append('')
        
        # Generate tables
        for table_name, table in self.tables.items():
            dbml_content.append(self._generate_table_dbml(table))
            dbml_content.append('')
        
        # Generate references
        dbml_content.append('// Relationships')
        # Try to use parsed relationships first, fallback to manual if none found
        auto_relationships = self._get_auto_relationships()
        if auto_relationships:
            for rel in auto_relationships:
                ref_line = f'Ref: {rel["from_table"]}.{rel["from_column"]} > {rel["to_table"]}.{rel["to_column"]}'
                dbml_content.append(ref_line)
        else:
            # Fallback to manual relationships
            manual_relationships = self._get_manual_relationships()
            for rel in manual_relationships:
                ref_line = f'Ref: {rel["from_table"]}.{rel["from_column"]} > {rel["to_table"]}.{rel["to_column"]}'
                dbml_content.append(ref_line)
        
        return '\n'.join(dbml_content)
    
    def _generate_table_dbml(self, table: Table) -> str:
        """Tạo DBML cho một bảng"""
        lines = []
        
        # Table header với note
        table_note = self._get_table_note(table.name)
        lines.append(f'Table {table.name} {{')
        if table_note:
            lines.append(f'  Note: "{table_note}"')
        
        # Columns
        for column in table.columns:
            column_line = self._generate_column_dbml(column)
            lines.append(f'  {column_line}')
        
        # Table constraints
        if table.constraints:
            lines.append('')
            lines.append('  // Table constraints')
            for constraint in table.constraints:
                lines.append(f'  // {constraint}')
        
        # Indexes
        if table.indexes:
            lines.append('')
            lines.append('  Indexes {')
            for index in table.indexes:
                lines.append(f'    {index}')
            lines.append('  }')
        
        lines.append('}')
        return '\n'.join(lines)
    
    def _generate_column_dbml(self, column: Column) -> str:
        """Tạo DBML cho một cột"""
        # Basic column definition
        column_def = f'{column.name} {self._convert_data_type(column.data_type)}'
        
        # Add only supported attributes (pk, unique)
        attributes = []
        
        if column.is_primary_key:
            attributes.append('pk')
        
        if 'UNIQUE' in column.constraints:
            attributes.append('unique')
        
        # Add attributes to column definition
        if attributes:
            attr_str = ', '.join(attributes)
            column_def += f' [{attr_str}]'
        
        # Add note with additional info
        note_parts = []
        
        if column.is_foreign_key:
            note_parts.append(f'FK -> {column.references_table}.{column.references_column}')
        
        if column.is_not_null and not column.is_primary_key:
            note_parts.append('NOT NULL')
        
        if column.default_value:
            default_val = self._format_default_value(column.default_value)
            note_parts.append(f'default: {default_val}')
        
        if 'CHECK' in ' '.join(column.constraints):
            note_parts.append('has constraints')
        
        if note_parts:
            column_def += f' // {", ".join(note_parts)}'
        
        return column_def
    
    def _convert_data_type(self, pg_type: str) -> str:
        """Chuyển đổi PostgreSQL data type sang DBML"""
        type_mapping = {
            'SERIAL': 'int',
            'INTEGER': 'int',
            'BIGINT': 'bigint',
            'SMALLINT': 'smallint',
            'DECIMAL': 'decimal',
            'NUMERIC': 'decimal',
            'REAL': 'float',
            'DOUBLE PRECISION': 'double',
            'BOOLEAN': 'boolean',
            'CHAR': 'char',
            'VARCHAR': 'varchar',
            'TEXT': 'text',
            'DATE': 'date',
            'TIME': 'time',
            'TIMESTAMP': 'timestamp',
            'TIMESTAMPTZ': 'timestamptz',
            'JSON': 'json',
            'JSONB': 'jsonb'
        }
        
        # Handle types with parameters like VARCHAR(100)
        base_type = pg_type.split('(')[0].upper()
        if base_type in type_mapping:
            if '(' in pg_type:
                # Keep the parameters
                return pg_type.lower().replace(base_type.lower(), type_mapping[base_type])
            else:
                return type_mapping[base_type]
        
        return pg_type.lower()
    
    def _format_default_value(self, default_value: str) -> str:
        """Format default value cho DBML"""
        default_value = default_value.strip()
        
        # Special PostgreSQL defaults
        if default_value.upper() == 'CURRENT_TIMESTAMP':
            return '`now()`'
        elif default_value.upper() == 'CURRENT_DATE':
            return '`now()`'
        elif default_value.upper() in ['TRUE', 'FALSE']:
            return default_value.lower()
        elif default_value.isdigit():
            return default_value
        else:
            return f'"{default_value}"'
    
    def _get_table_note(self, table_name: str) -> str:
        """Lấy note cho bảng"""
        table_notes = {
            'product_categories': 'Danh mục sản phẩm',
            'suppliers': 'Nhà cung cấp',
            'products': 'Sản phẩm',
            'discount_rules': 'Quy tắc giảm giá',
            'warehouse': 'Kho hàng',
            'warehouse_inventory': 'Tồn kho trong kho',
            'display_shelves': 'Quầy hàng trưng bày',
            'shelf_layout': 'Bố trí sản phẩm trên quầy',
            'shelf_inventory': 'Tồn kho trên quầy',
            'positions': 'Vị trí công việc',
            'employees': 'Nhân viên',
            'employee_work_hours': 'Giờ làm việc nhân viên',
            'membership_levels': 'Hạng thành viên',
            'customers': 'Khách hàng',
            'sales_invoices': 'Hóa đơn bán hàng',
            'sales_invoice_details': 'Chi tiết hóa đơn',
            'purchase_orders': 'Đơn đặt hàng',
            'purchase_order_details': 'Chi tiết đơn hàng',
            'stock_transfers': 'Chuyển kho'
        }
        return table_notes.get(table_name, '')
    
    def _get_auto_relationships(self) -> list:
        """Lấy relationships tự động từ parsed foreign keys"""
        relationships = []
        
        for table in self.tables.values():
            for fk in table.foreign_keys:
                relationship = {
                    "from_table": table.name,
                    "from_column": fk.column,
                    "to_table": fk.references_table,
                    "to_column": fk.references_column
                }
                relationships.append(relationship)
        
        return relationships
    
    def _get_manual_relationships(self) -> list:
        """Tạo relationships thủ công vì parser chưa tự động parse được"""
        relationships = [
            # Products relationships
            {"from_table": "products", "from_column": "category_id", "to_table": "product_categories", "to_column": "category_id"},
            {"from_table": "products", "from_column": "supplier_id", "to_table": "suppliers", "to_column": "supplier_id"},
            
            # Discount rules
            {"from_table": "discount_rules", "from_column": "category_id", "to_table": "product_categories", "to_column": "category_id"},
            
            # Warehouse inventory
            {"from_table": "warehouse_inventory", "from_column": "warehouse_id", "to_table": "warehouse", "to_column": "warehouse_id"},
            {"from_table": "warehouse_inventory", "from_column": "product_id", "to_table": "products", "to_column": "product_id"},
            
            # Display shelves
            {"from_table": "display_shelves", "from_column": "category_id", "to_table": "product_categories", "to_column": "category_id"},
            
            # Shelf layout
            {"from_table": "shelf_layout", "from_column": "shelf_id", "to_table": "display_shelves", "to_column": "shelf_id"},
            {"from_table": "shelf_layout", "from_column": "product_id", "to_table": "products", "to_column": "product_id"},
            
            # Shelf inventory
            {"from_table": "shelf_inventory", "from_column": "shelf_id", "to_table": "display_shelves", "to_column": "shelf_id"},
            {"from_table": "shelf_inventory", "from_column": "product_id", "to_table": "products", "to_column": "product_id"},
            
            # Employees
            {"from_table": "employees", "from_column": "position_id", "to_table": "positions", "to_column": "position_id"},
            
            # Employee work hours
            {"from_table": "employee_work_hours", "from_column": "employee_id", "to_table": "employees", "to_column": "employee_id"},
            
            # Customers
            {"from_table": "customers", "from_column": "membership_level_id", "to_table": "membership_levels", "to_column": "level_id"},
            
            # Sales invoices
            {"from_table": "sales_invoices", "from_column": "customer_id", "to_table": "customers", "to_column": "customer_id"},
            {"from_table": "sales_invoices", "from_column": "employee_id", "to_table": "employees", "to_column": "employee_id"},
            
            # Sales invoice details
            {"from_table": "sales_invoice_details", "from_column": "invoice_id", "to_table": "sales_invoices", "to_column": "invoice_id"},
            {"from_table": "sales_invoice_details", "from_column": "product_id", "to_table": "products", "to_column": "product_id"},
            
            # Purchase orders
            {"from_table": "purchase_orders", "from_column": "supplier_id", "to_table": "suppliers", "to_column": "supplier_id"},
            {"from_table": "purchase_orders", "from_column": "employee_id", "to_table": "employees", "to_column": "employee_id"},
            
            # Purchase order details
            {"from_table": "purchase_order_details", "from_column": "order_id", "to_table": "purchase_orders", "to_column": "order_id"},
            {"from_table": "purchase_order_details", "from_column": "product_id", "to_table": "products", "to_column": "product_id"},
            
            # Stock transfers
            {"from_table": "stock_transfers", "from_column": "product_id", "to_table": "products", "to_column": "product_id"},
            {"from_table": "stock_transfers", "from_column": "from_warehouse_id", "to_table": "warehouse", "to_column": "warehouse_id"},
            {"from_table": "stock_transfers", "from_column": "to_shelf_id", "to_table": "display_shelves", "to_column": "shelf_id"},
            {"from_table": "stock_transfers", "from_column": "employee_id", "to_table": "employees", "to_column": "employee_id"},
        ]
        return relationships
    
    def save_dbml(self, file_path: str):
        """Lưu DBML vào file"""
        dbml_content = self.generate_dbml()
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(dbml_content)
    
    def generate_table_groups(self) -> str:
        """Tạo table groups cho DBML"""
        groups = {
            'Product Management': [
                'product_categories', 'suppliers', 'products', 'discount_rules'
            ],
            'Inventory Management': [
                'warehouse', 'warehouse_inventory', 'display_shelves', 
                'shelf_layout', 'shelf_inventory', 'stock_transfers'
            ],
            'Employee Management': [
                'positions', 'employees', 'employee_work_hours'
            ],
            'Customer Management': [
                'membership_levels', 'customers'
            ],
            'Sales Management': [
                'sales_invoices', 'sales_invoice_details'
            ],
            'Purchase Management': [
                'purchase_orders', 'purchase_order_details'
            ]
        }
        
        group_lines = []
        for group_name, tables in groups.items():
            group_lines.append(f'TableGroup "{group_name}" {{')
            for table in tables:
                if table in self.tables:
                    group_lines.append(f'  {table}')
            group_lines.append('}')
            group_lines.append('')
        
        return '\n'.join(group_lines)
    
    def generate_full_dbml(self) -> str:
        """Tạo DBML đầy đủ với table groups"""
        basic_dbml = self.generate_dbml()
        groups_dbml = self.generate_table_groups()
        
        return f'{basic_dbml}\n\n// Table Groups\n{groups_dbml}'


if __name__ == "__main__":
    # Test generator
    from sql_parser import SQLParser
    
    parser = SQLParser()
    tables = parser.parse_sql_file('../sql/01_schema.sql')
    
    generator = DBMLGenerator()
    generator.load_tables(tables)
    
    # Generate and save DBML
    generator.save_dbml('supermarket.dbml')
    print("Đã tạo file supermarket.dbml")
    
    # Generate full DBML with groups
    full_dbml = generator.generate_full_dbml()
    with open('supermarket_full.dbml', 'w', encoding='utf-8') as f:
        f.write(full_dbml)
    print("Đã tạo file supermarket_full.dbml với table groups")
