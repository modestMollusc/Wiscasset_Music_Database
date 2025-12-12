# Wiscasset Music Database

## 1. Specifications for Building the Project

This project consists of a PostgreSQL database for managing music products, orders, customers, and inventory at Wiscasset Music, along with a Python-based GUI application for interacting with the database. The source files include:
- `dump-wiscasset-202512112335.sql`: A PostgreSQL database dump file containing the schema, data, functions, triggers, and views.
- `wisc4.py`: The Python GUI application using Tkinter for the user interface and psycopg for database connectivity.

### Prerequisites
- **Operating System**: Windows, macOS, or Linux (tested on macOS and Linux).
- **Software**:
  - PostgreSQL 17.x (or compatible version; the dump was created with PostgreSQL 17.6).
  - Python 3.8+ (recommended 3.12+ for compatibility with libraries).
- **Python Libraries**:
  - `tkinter`: Built-in with Python (for GUI components).
  - `psycopg`: Version 3.x (for PostgreSQL connectivity). Install via pip: `pip install psycopg[binary]` (the binary option is recommended to avoid compilation issues).
  - `datetime`: Built-in (for date handling).
  - No other external libraries are required beyond these.

### Installation and Setup Steps
1. **Install PostgreSQL**:
   - Download and install from the official website: [PostgreSQL Downloads](https://www.postgresql.org/download/).
   - Ensure the `psql` command-line tool is available in your PATH.

2. **Create the Database and User**:
   - Open a terminal or command prompt.
   - Log in as the PostgreSQL superuser (default is `postgres`):
     ```
     psql -U postgres
     ```
   - Run the following SQL commands to create the database and user (replace passwords as needed for security):
     ```
     CREATE DATABASE wiscasset;
     CREATE USER your_username WITH PASSWORD 'your_password';
     GRANT ALL PRIVILEGES ON DATABASE wiscasset TO your_username;
     ```
   - Exit psql with `\q`.

3. **Restore the Database from the Dump**:
   - The dump file (`dump-wiscasset-202512112335.sql`) includes custom commands like `\restrict` and `\unrestrict` (possibly for access control or custom extensions). If these cause errors, comment them out or consult PostgreSQL documentation for handling non-standard dumps.
   - Restore the dump:
     ```
     psql -U your_username -d wiscasset -f dump-wiscasset-202512112335.sql
     ```
   - Verify the restore by connecting to the database:
     ```
     psql -U your_username -d wiscasset
     ```
     - Run `\dt` to list tables (e.g., `customer`, `orders`, `music_product`).
     - Exit with `\q`.

4. **Install Python Dependencies**:
   - Ensure Python is installed (download from [python.org](https://www.python.org/)).
   - Install psycopg:
     ```
     pip install psycopg[binary]
     ```

5. **Run the Application**:
   - Place `wisc4.py` in your working directory.
   - Ensure the database is running (PostgreSQL service should be active).
   - Run the script:
     ```
     python wisc4.py
     ```
   - The GUI will launch with tabs for Orders, Customers, Product Search, Add Music Product, and Replenish Inventory.

### Troubleshooting
- **Connection Errors**: Verify DB_CONFIG in `wisc4.py` matches your setup (host: localhost, dbname: wiscasset, user: your_username, password: your_password).
- **Library Issues**: If tkinter is missing, install it via your OS package manager (e.g., `sudo apt install python3-tk` on Ubuntu).
- **Dump Restore Fails**: If `\restrict` commands error out, edit the .sql file to remove them and retry.
- **Permissions**: Ensure the user `your_username` has full access; run `GRANT ALL ON SCHEMA public TO your_username;` if needed.

## 2. Technical Specifications

### Overview
The Wiscasset Music Database is a relational database system with a desktop GUI for managing sheet music inventory, orders, customers, and products. It focuses on compositions by B. Warren and supports operations like order creation, customer management, product searches, adding new music products, and inventory replenishment.

### Database Specifications
- **RDBMS**: PostgreSQL 17.6 (compatible with 17.x+).
- **Schema**: Public schema with the following key components:
  - **Tables**:
    - `category`: Stores music categories (e.g., Winds, Keyboard).
    - `customer`: Customer details (ID, name, email, address).
    - `inventory`: Product stock levels by location.
    - `inventory_halstan_staging`: Staging for Halstan inventory imports.
    - `inventory_movement`: Logs inventory changes (e.g., sales, adjustments).
    - `location`: Storage locations (e.g., warehouses).
    - `music_product`: Core product catalog (title, composer, price, ISBN, etc.; 20+ attributes including duration, media, score type).
    - `order_line`: Line items for orders (links to products and orders).
    - `orders`: Order headers (date, customer ID).
    - `product_category_junction`: Many-to-many link between products and categories.
  - **Sequences**: Auto-incrementing IDs for tables like `category_category_id_seq`, `customer_customer_id_seq`, etc.
  - **Functions & Triggers**:
    - `order_line_inventory_movement()`: PL/pgSQL function triggered on INSERT/UPDATE/DELETE of order lines to update inventory and log movements.
  - **Views**:
    - `customer_order_summary`: Aggregates order counts and total spent per customer.
    - `inventory_with_location`: Joins inventory with product titles and location names.
    - `music_product_with_primary_category`: Products with prioritized categories.
    - `orders_with_total`: Orders with calculated totals.
- **Data Integrity**:
  - Primary keys, unique constraints (e.g., inventory by product/location).
  - Foreign keys (e.g., order_line to orders and music_product).
  - Generated columns (e.g., line_total in order_line).
  - Constraints: NOT NULL on key fields like product_id in music_product.
- **Initial Data**: The dump includes sample customers (e.g., Citizen Kane), products (91 entries), orders (22), and inventory.

### Application Specifications
- **Language & Framework**: Python 3, with Tkinter for GUI (ttk for themed widgets, messagebox for alerts).
- **Dependencies**: psycopg (for DB queries), datetime (for dates).
- **Features & Tabs**:
  - **Orders**: Create orders, add lines, view invoices, refresh lines with totals.
  - **Customers**: Save/update customers, load by ID, clear form.
  - **Product Search**: Filter by category/composer/media/type; display results with inventory qty; select for orders.
  - **Add Music Product**: Comprehensive form with dropdowns for all music_product attributes; multi-select categories; add/update modes; validation; auto-ID generation.
  - **Replenish Inventory**: Add stock with product check, display title, undo last entry, clear form.
- **Database Interaction**:
  - Connection: Via psycopg with hardcoded config (host: localhost, db: wiscasset, user: your_username, password: your_password).
  - Queries: Prepared statements for security; handles inserts, updates, selects.
  - Error Handling: Messageboxes for DB errors.
- **GUI Elements**:
  - Notebook tabs for navigation.
  - Treeviews for lists (e.g., order lines, products).
  - Comboboxes for filters/dropdowns (populated from DB).
  - Validation: Input checks (e.g., integers, required fields).
- **Security Notes**: Hardcoded credentials—use environment variables in production. No authentication in app.
- **Extensibility**: Modular functions (e.g., add_order_line, refresh_order_lines); easy to add tabs or fields.

### Usage Notes
- Run on a local PostgreSQL instance for development.
- For production, secure credentials and add backups.
- Tested with sample data; scale tested up to hundreds of products/orders.

For issues or contributions, refer to the source files or contact the developer.