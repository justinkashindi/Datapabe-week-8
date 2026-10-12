// --- ENTITIES & ATTRIBUTES ---

Table users {
  id integer [primary key, increment]
  full_name varchar(100) [not null]
  email varchar(255) [unique, not null]
  password_hash varchar(255) [not null]
  phone varchar(20)
  created_at timestamp [default: `now()`]
}

Table products {
  id integer [primary key, increment]
  name varchar(255) [not null]
  description text
  price decimal(10,2) [not null]
  stock_quantity integer [not null, default: 0]
  created_at timestamp [default: `now()`]
}

Table orders {
  id integer [primary key, increment]
  user_id integer [not null]
  status varchar(50) [not null, default: 'Pending']
  total_amount decimal(10,2) [not null]
  created_at timestamp [default: `now()`]
}

Table order_items {
  id integer [primary key, increment]
  order_id integer [not null]
  product_id integer [not null]
  quantity integer [not null, default: 1]
  price_at_purchase decimal(10,2) [not null]
}

Table payments {
  id integer [primary key, increment]
  order_id integer [unique, not null]
  payment_method varchar(50) [not null]
  transaction_status varchar(50) [not null]
  amount_paid decimal(10,2) [not null]
  processed_at timestamp [default: `now()`]
}

// --- RELATIONSHIPS & CARDINALITIES ---

// One-to-Many: One user can place many orders
Ref: users.id < orders.user_id 

// One-to-Many: One order can contain multiple line items
Ref: orders.id < order_items.order_id

// One-to-Many: One product can be tied to multiple order items
Ref: products.id < order_items.product_id

// One-to-One: One order maps to exactly one payment transaction
Ref: orders.id - payments.order_id

-- Create users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create products table
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create orders table
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status VARCHAR(50) NOT NULL DEFAULT 'Pending',
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create order_items table
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    price_at_purchase DECIMAL(10,2) NOT NULL CHECK (price_at_purchase >= 0),
    CONSTRAINT unique_order_product UNIQUE (order_id, product_id)
);

-- Create payments table
CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    order_id INTEGER UNIQUE NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    payment_method VARCHAR(50) NOT NULL,
    transaction_status VARCHAR(50) NOT NULL,
    amount_paid DECIMAL(10,2) NOT NULL CHECK (amount_paid >= 0),
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- Performance Optimization Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_payments_order_id ON payments(order_id);


-- Setup global audit table to track structural record histories
CREATE TABLE audit_log (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    action VARCHAR(20) NOT NULL,
    row_id INTEGER NOT NULL,
    changed_by VARCHAR(100) DEFAULT CURRENT_USER,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Reusable logic function for populating the audit trail
CREATE OR REPLACE FUNCTION process_audit_log()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log(table_name, action, row_id)
        VALUES (TG_RELNAME, TG_OP, OLD.id);
        RETURN OLD;
    ELSE
        INSERT INTO audit_log(table_name, action, row_id)
        VALUES (TG_RELNAME, TG_OP, NEW.id);
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Bind audit triggers to business entities
CREATE TRIGGER audit_users_trigger
AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION process_audit_log();

CREATE TRIGGER audit_products_trigger
AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW EXECUTE FUNCTION process_audit_log();

-- Inventory automation: Deduct stock automatically on order creation
CREATE OR REPLACE FUNCTION deduct_inventory_on_order()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE products
    SET stock_quantity = stock_quantity - NEW.quantity
    WHERE id = NEW.product_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_deduct_stock
AFTER INSERT ON order_items
FOR EACH ROW EXECUTE FUNCTION deduct_inventory_on_order();


-- Enable PostgreSQL Row Level Security (RLS)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Note: In a production setup, 'current_setting('app.current_user_id')' 
-- maps dynamically to the session variable populated by your app connection pool.

CREATE POLICY user_self_management ON users
    FOR ALL
    USING (id::text = current_setting('app.current_user_id', true));

CREATE POLICY order_customer_isolation ON orders
    FOR ALL
    USING (user_id::text = current_setting('app.current_user_id', true));

CREATE POLICY order_items_customer_isolation ON order_items
    FOR ALL
    USING (order_id IN (
        SELECT id FROM orders WHERE user_id::text = current_setting('app.current_user_id', true)
    ));

CREATE POLICY payment_customer_isolation ON payments
    FOR ALL
    USING (order_id IN (
        SELECT id FROM orders WHERE user_id::text = current_setting('app.current_user_id', true)
    ));


-- Seed baseline sample catalog and target platform users
INSERT INTO users (full_name, email, password_hash, phone) VALUES
('Alice Smith', 'alice@example.com', '$2b$12$ExAmPlEhAsH1234567890uUserOne', '+1555010011'),
('Bob Jones', 'bob@example.com', '$2b$12$ExAmPlEhAsH0987654321uUserTwo', '+1555010022');

INSERT INTO products (name, description, price, stock_quantity) VALUES
('Wireless Ergonomic Mouse', '2.4GHz silent vertical optical mouse', 29.99, 150),
('Mechanical Gaming Keyboard', 'RGB backlit blue switch clicky keyboard', 74.50, 45),
('USB-C Hub Multiport Adapter', '6-in-1 space gray aluminum dongle', 19.99, 300);

-- Insert an historical order for validation (Note: Triggers in V3 will automatically drop matching stock levels)
INSERT INTO orders (user_id, status, total_amount) VALUES
(1, 'Completed', 124.48);

INSERT INTO order_items (order_id, product_id, quantity, price_at_purchase) VALUES
(1, 1, 1, 29.99),
(1, 2, 1, 74.50),
(1, 3, 1, 19.99);

INSERT INTO payments (order_id, payment_method, transaction_status, amount_paid) VALUES
(1, 'Credit Card', 'Approved', 124.48);

