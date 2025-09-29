-- ============================================================================
-- VALIDATION TRIGGERS
-- ============================================================================

-- Validate Warehouse Inventory Quantity
CREATE OR REPLACE FUNCTION validate_warehouse_quantity()
RETURNS TRIGGER AS $$
BEGIN
    -- Ensure quantity is never negative (allow zero for transfers)
    IF NEW.quantity < 0 THEN
        RAISE EXCEPTION 'Cannot create warehouse inventory with negative quantity: % for product_id: %', 
                       NEW.quantity, NEW.product_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_validate_warehouse_quantity ON warehouse_inventory;
CREATE TRIGGER tr_validate_warehouse_quantity
    BEFORE INSERT ON warehouse_inventory
    FOR EACH ROW
    EXECUTE FUNCTION validate_warehouse_quantity();
