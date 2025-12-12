# CS5200 Database Management Systems
# James F. Davis
# File name: wisc5G.py
# The Wiscasset Music Publishing catalog and inventory management front end application
# 
# Works in conjunction with the "wiscasset" PostgreSQL database
# Currently using Wiscasset_schema9.sql
#
# Code version wisc5G.py updated 12 Dec, 2025
# Notes:
# - Upgraded the "Add Music Product" tab to fix the automatic addition of
# - a product_id number (primary key in the music_product table)      
# - Added default pulldown menus to mimic format of the "product search" tab
# - Added multi-select for categories
# - Added input fields for all attribute columns with defaults
# - Added update product feature to change product attributes such as price
# - Added a product_id check on the replenish inventory tab
# - fixed an obscured button on the replenish inventory tab

import tkinter as tk
from tkinter import ttk, messagebox
import psycopg
from datetime import date

DB_CONFIG = {
    "host": "localhost",
    "dbname": "wiscasset",
    "user": "Insert_your_username_here",
    "password": "Insert_your_password_here",
}

def get_connection():
    return psycopg.connect(**DB_CONFIG)


# =========================
# ORDER FUNCTIONS
# =========================

def create_order():
    customer_id = customer_id_var.get().strip()
    if not customer_id:
        messagebox.showerror("Error", "Customer ID is required to create an order.")
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO public.orders (order_date, customer_id)
            VALUES (%s, %s)
            RETURNING order_id
            """,
            (date.today(), int(customer_id))
        )
        new_order_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()

        order_id_var.set(str(new_order_id))
        refresh_order_lines()
        messagebox.showinfo("Order Created", f"Order {new_order_id} created.")
    except Exception as e:
        messagebox.showerror("Database Error", f"Error creating order:\n{e}")


def add_order_line():
    order_id = order_id_var.get().strip()
    product_id = product_id_var.get().strip()
    qty = quantity_var.get().strip()
    price = price_var.get().strip()
    location_id = location_id_var.get().strip()

    if not order_id:
        messagebox.showerror("Error", "Order ID is required. Create an order first.")
        return
    if not product_id:
        messagebox.showerror("Error", "Product ID is required.")
        return
    if not qty:
        messagebox.showerror("Error", "Quantity is required.")
        return
    if not price:
        messagebox.showerror("Error", "Unit Price is required.")
        return
    if price.lower() == "none":
        messagebox.showerror("Error", "This product has no price set in the catalog. Please enter a price.")
        return
    if not location_id:
        messagebox.showerror("Error", "Location ID is required.")
        return

    price_clean = price.replace("$", "").replace(",", "").strip()

    try:
        order_id_val = int(order_id)
    except ValueError:
        messagebox.showerror("Error", f"Order ID must be a number, got: {order_id!r}")
        return

    try:
        product_id_val = int(product_id)
    except ValueError:
        messagebox.showerror("Error", f"Product ID must be a number, got: {product_id!r}")
        return

    try:
        qty_val = int(qty)
    except ValueError:
        messagebox.showerror("Error", f"Quantity must be a whole number, got: {qty!r}")
        return

    try:
        price_val = float(price_clean)
    except ValueError:
        messagebox.showerror("Error", f"Unit Price must be a number, got: {price!r}")
        return

    try:
        location_id_val = int(location_id)
    except ValueError:
        messagebox.showerror("Error", f"Location ID must be a number, got: {location_id!r}")
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO public.order_line
                (order_id, product_id, fulfilled_from_location_id, quantity, product_price)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (order_id_val, product_id_val, location_id_val, qty_val, price_val)
        )
        conn.commit()
        cur.close()
        conn.close()

        refresh_order_lines()
        messagebox.showinfo(
            "Line Added",
            "Order line added and inventory adjusted (via triggers, if enabled)."
        )
    except Exception as e:
        messagebox.showerror("Database Error", f"Error adding order line:\n{e}")


def refresh_order_lines():
    """Load all order lines for the current order into the Treeview."""
    oid = order_id_var.get().strip()
    for item in order_lines_tree.get_children():
        order_lines_tree.delete(item)
    if not oid:
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            """
            SELECT
                ol.order_line_id,
                mp.title,
                ol.product_id,
                ol.quantity,
                ol.product_price,
                ol.line_total
            FROM public.order_line ol
            JOIN public.music_product mp
              ON mp.product_id = ol.product_id
            WHERE ol.order_id = %s
            ORDER BY ol.order_line_id;
            """,
            (int(oid),)
        )
        rows = cur.fetchall()
        cur.close()
        conn.close()
    except Exception as e:
        messagebox.showerror("Database Error", f"Error loading order lines:\n{e}")
        return

    for line_id, title, pid, qty, price, total in rows:
        order_lines_tree.insert(
            "",
            "end",
            values=(line_id, pid, title, qty, price, total)
        )


def show_invoice():
    """Open a simple printable-like invoice window for current order."""
    oid = order_id_var.get().strip()
    if not oid:
        messagebox.showerror("Error", "No order selected.")
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        # Header: order + customer
        cur.execute(
            """
            SELECT
                o.order_id,
                o.order_date,
                c.first_name,
                c.last_name,
                c.street_address,
                c.town,
                c.zip,
                c.country
            FROM public.orders o
            LEFT JOIN public.customer c
              ON c.customer_id = o.customer_id
            WHERE o.order_id = %s;
            """,
            (int(oid),)
        )
        header = cur.fetchone()
        if not header:
            messagebox.showerror("Error", f"Order {oid} not found.")
            cur.close()
            conn.close()
            return

        # Lines
        cur.execute(
            """
            SELECT
                mp.title,
                ol.quantity,
                ol.product_price,
                ol.line_total
            FROM public.order_line ol
            JOIN public.music_product mp
              ON mp.product_id = ol.product_id
            WHERE ol.order_id = %s
            ORDER BY ol.order_line_id;
            """,
            (int(oid),)
        )
        lines = cur.fetchall()
        cur.close()
        conn.close()
    except Exception as e:
        messagebox.showerror("Database Error", f"Error building invoice:\n{e}")
        return

    (order_id_val, order_date, first, last, street, town, zip_code, country) = header

    total = sum(l[3] for l in lines) if lines else 0

    win = tk.Toplevel(root)
    win.title(f"Invoice #{order_id_val}")

    txt = tk.Text(win, width=80, height=30)
    txt.pack(fill="both", expand=True)

    txt.insert("end", f"Wiscasset Music\n")
    txt.insert("end", f"Invoice #: {order_id_val}\n")
    txt.insert("end", f"Date: {order_date}\n\n")

    txt.insert("end", "Bill To:\n")
    name_line = " ".join(x for x in [first, last] if x)
    txt.insert("end", f"{name_line}\n" if name_line else "(no name)\n")
    if street:
        txt.insert("end", f"{street}\n")
    city_line = ", ".join(x for x in [town, zip_code] if x)
    if city_line:
        txt.insert("end", f"{city_line}\n")
    if country:
        txt.insert("end", f"{country}\n")
    txt.insert("end", "\n")

    txt.insert("end", f"{'Title':50} {'Qty':>5} {'Price':>10} {'Total':>10}\n")
    txt.insert("end", "-" * 80 + "\n")
    for title, qty, price, line_total in lines:
        title_short = (title[:47] + "...") if len(title) > 50 else title
        txt.insert(
            "end",
            f"{title_short:50} {qty:>5} {price:>10.2f} {line_total:>10.2f}\n"
        )
    txt.insert("end", "-" * 80 + "\n")
    txt.insert("end", f"{'TOTAL':>70} {total:>10.2f}\n")

    txt.config(state="disabled")
    # User can use OS print dialog from here


# =========================
# CUSTOMER FUNCTIONS
# =========================

def save_customer():
    first_name = cust_first_name_var.get().strip()
    last_name = cust_last_name_var.get().strip()
    email = cust_email_var.get().strip()
    phone = cust_phone_var.get().strip()
    street = cust_street_var.get().strip()
    town = cust_town_var.get().strip()
    zip_code = cust_zip_var.get().strip()
    country = cust_country_var.get().strip()

    if not (first_name or last_name):
        messagebox.showerror("Error", "At least a first or last name is required.")
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO public.customer
                (first_name, last_name, email_addr, phone,
                 street_address, town, zip, country)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING customer_id
            """,
            (first_name, last_name, email, phone, street, town, zip_code, country)
        )
        new_customer_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()

        messagebox.showinfo("Customer Saved", f"Customer {new_customer_id} created.")
        customer_id_var.set(str(new_customer_id))
        cust_lookup_id_var.set(str(new_customer_id))
    except Exception as e:
        messagebox.showerror("Database Error", f"Error saving customer:\n{e}")


def clear_customer_form():
    cust_first_name_var.set("")
    cust_last_name_var.set("")
    cust_email_var.set("")
    cust_phone_var.set("")
    cust_street_var.set("")
    cust_town_var.set("")
    cust_zip_var.set("")
    cust_country_var.set("")
    cust_lookup_id_var.set("")


def load_customer():
    cid = cust_lookup_id_var.get().strip()
    if not cid:
        messagebox.showerror("Error", "Enter a Customer ID to load.")
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            """
            SELECT
                first_name, last_name, email_addr, phone,
                street_address, town, zip, country
            FROM public.customer
            WHERE customer_id = %s;
            """,
            (int(cid),)
        )
        row = cur.fetchone()
        cur.close()
        conn.close()
    except Exception as e:
        messagebox.showerror("Database Error", f"Error loading customer:\n{e}")
        return

    if not row:
        messagebox.showerror("Error", f"No customer with ID {cid} found.")
        return

    first, last, email, phone, street, town, zip_code, country = row
    cust_first_name_var.set(first or "")
    cust_last_name_var.set(last or "")
    cust_email_var.set(email or "")
    cust_phone_var.set(phone or "")
    cust_street_var.set(street or "")
    cust_town_var.set(town or "")
    cust_zip_var.set(zip_code or "")
    cust_country_var.set(country or "")


# =========================
# PRODUCT SEARCH FUNCTIONS
# =========================

def load_filter_options():
    try:
        conn = get_connection()
        cur = conn.cursor()

        # Categories
        cur.execute("SELECT category_name FROM public.category ORDER BY category_name;")
        cats = [row[0] for row in cur.fetchall()]
        category_values = ["(Any category)"] + cats
        search_category_combo["values"] = category_values
        search_category_var.set("(Any category)")

        # Composers
        cur.execute("""
            SELECT DISTINCT composer
            FROM public.music_product
            WHERE composer IS NOT NULL
            ORDER BY composer;
        """)
        composers = [row[0] for row in cur.fetchall()]
        search_composer_combo["values"] = composers
        if "B. Warren" in composers:
            search_composer_var.set("B. Warren")
        elif composers:
            search_composer_var.set(composers[0])
        else:
            search_composer_var.set("")

        # Media
        cur.execute("""
            SELECT DISTINCT media
            FROM public.music_product
            WHERE media IS NOT NULL
            ORDER BY media;
        """)
        medias = [row[0] for row in cur.fetchall()]
        media_values = ["(Any media)"] + medias
        search_media_combo["values"] = media_values
        if "print" in medias:
            search_media_var.set("print")
        else:
            search_media_var.set("(Any media)")

        # Product types
        cur.execute("""
            SELECT DISTINCT product_type
            FROM public.music_product
            WHERE product_type IS NOT NULL
            ORDER BY product_type;
        """)
        ptypes = [row[0] for row in cur.fetchall()]
        ptype_values = ["(Any type)"] + ptypes
        search_product_type_combo["values"] = ptype_values
        if "Sheet Music" in ptypes:
            search_product_type_var.set("Sheet Music")
        else:
            search_product_type_var.set("(Any type)")

        cur.close()
        conn.close()
    except Exception as e:
        messagebox.showerror("Database Error", f"Error loading filter options:\n{e}")


def clear_product_search():
    search_category_var.set("(Any category)")
    search_composer_var.set("")
    search_media_var.set("(Any media)")
    search_product_type_var.set("(Any type)")
    for item in product_tree.get_children():
        product_tree.delete(item)


def run_product_search():
    cat_name = search_category_var.get().strip()
    composer = search_composer_var.get().strip()
    media = search_media_var.get().strip()
    ptype = search_product_type_var.get().strip()

    query = """
        SELECT
            mp.product_id,
            mp.title,
            mp.composer,
            mp.media,
            mp.product_type,
            mp.price,
            COALESCE(SUM(i.quantity), 0) AS qty
        FROM public.music_product mp
        LEFT JOIN public.inventory i
          ON i.product_id = mp.product_id
    """
    joins = []
    where_clauses = []
    params = []

    if cat_name and cat_name != "(Any category)":
        joins.append("""
            JOIN public.product_category_junction pcj
              ON pcj.product_id = mp.product_id
            JOIN public.category c
              ON c.category_id = pcj.category_id
        """)
        where_clauses.append("c.category_name = %s")
        params.append(cat_name)

    if composer:
        where_clauses.append("mp.composer = %s")
        params.append(composer)

    if media and media != "(Any media)":
        where_clauses.append("mp.media = %s")
        params.append(media)

    if ptype and ptype != "(Any type)":
        where_clauses.append("mp.product_type = %s")
        params.append(ptype)

    if joins:
        query += " " + " ".join(joins)
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    query += """
        GROUP BY
            mp.product_id,
            mp.title,
            mp.composer,
            mp.media,
            mp.product_type,
            mp.price
        ORDER BY mp.title;
    """

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(query, tuple(params))
        rows = cur.fetchall()
        cur.close()
        conn.close()
    except Exception as e:
        messagebox.showerror("Database Error", f"Error searching products:\n{e}")
        return

    for item in product_tree.get_children():
        product_tree.delete(item)

    for product_id, title, comp, med, ptype, price, qty in rows:
        product_tree.insert(
            "",
            "end",
            values=(product_id, title, comp, med, ptype, price, qty)
        )

    if not rows:
        messagebox.showinfo("Search", "No products found for the selected criteria.")


def use_selected_product_for_order():
    selected = product_tree.selection()
    if not selected:
        messagebox.showerror("Error", "Please select a product from the list.")
        return

    item_id = selected[0]
    values = product_tree.item(item_id, "values")
    # (product_id, title, composer, media, product_type, price, qty)
    prod_id = values[0]
    price = values[5]

    product_id_var.set(str(prod_id))
    if price is not None:
        price_var.set(str(price))
    notebook.select(order_frame)
    messagebox.showinfo("Product Selected", f"Product {prod_id} copied to order line fields.")


# =========================
# MUSIC PRODUCT FUNCTIONS
# =========================

def load_music_product():
    pid = mp_lookup_pid_var.get().strip()
    if not pid:
        messagebox.showerror("Error", "Enter a Product ID to load.")
        return

    try:
        pid_val = int(pid)
    except ValueError:
        messagebox.showerror("Error", "Product ID must be an integer.")
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT title, duration, no_of_movements, duration_seconds, duration_formatted,
                   price, ismn, is_duplicate, work_id, not_difficult, rentable, halstan_code,
                   composer, librettist_1, librettist_2, media, sheet_music_plus_sku, score_type,
                   publication_year, isbn, product_type
            FROM public.music_product
            WHERE product_id = %s;
        """, (pid_val,))
        row = cur.fetchone()

        if not row:
            messagebox.showerror("Error", f"No product with ID {pid} found.")
            cur.close()
            conn.close()
            return

        # Populate fields
        mp_title_var.set(row[0] or "")
        mp_duration_var.set(row[1] or "")
        mp_no_mov_var.set(str(row[2]) if row[2] is not None else "")
        mp_dur_sec_var.set(str(row[3]) if row[3] is not None else "")
        mp_dur_fmt_var.set(row[4] or "")
        mp_price_var.set(row[5] or "")
        mp_ismn_var.set(row[6] or "")
        mp_is_dup_var.set(row[7] or False)
        mp_work_id_var.set(str(row[8]) if row[8] is not None else "")
        mp_not_diff_var.set(row[9] or False)
        mp_rentable_var.set(row[10] or False)
        mp_halstan_var.set(row[11] or "")
        mp_composer_var.set(row[12] or "(None)")
        mp_lib1_var.set(row[13] or "(None)")
        mp_lib2_var.set(row[14] or "(None)")
        mp_media_var.set(row[15] or "(None)")
        mp_smp_sku_var.set(row[16] or "")
        mp_score_type_var.set(row[17] or "(None)")
        mp_pub_year_var.set(str(row[18]) if row[18] is not None else "")
        mp_isbn_var.set(row[19] or "")
        mp_product_type_var.set(row[20] or "(None)")

        # Load categories
        category_listbox.selection_clear(0, "end")
        cur.execute("""
            SELECT c.category_name
            FROM public.product_category_junction pcj
            JOIN public.category c ON c.category_id = pcj.category_id
            WHERE pcj.product_id = %s;
        """, (pid_val,))
        selected_cats = [r[0] for r in cur.fetchall()]
        for i, name in enumerate(category_names):
            if name in selected_cats:
                category_listbox.selection_set(i)

        mp_product_id_display_var.set(str(pid_val))
        messagebox.showinfo("Loaded", f"Product {pid_val} loaded for editing.")

        cur.close()
        conn.close()
    except Exception as e:
        messagebox.showerror("Database Error", f"Error loading product:\n{e}")

def update_music_product():
    pid_str = mp_product_id_display_var.get().strip()
    if not pid_str:
        messagebox.showerror("Error", "Load a product first to update.")
        return

    try:
        pid_val = int(pid_str)
    except ValueError:
        messagebox.showerror("Error", "Invalid Product ID.")
        return

    title = mp_title_var.get().strip()
    if not title:
        messagebox.showerror("Error", "Title is required.")
        return

    # Helper to get string or None
    def get_str(var):
        val = var.get().strip()
        return val if val else None

    # Helper to get int or None
    def get_int(var):
        val = var.get().strip()
        if not val:
            return None
        try:
            return int(val)
        except ValueError:
            messagebox.showerror("Error", f"Invalid integer: {val}")
            raise

    # Helper to get str for combo, handling "(None)"
    def get_combo_str(var):
        val = var.get().strip()
        return None if val == "(None)" or not val else val

    # Get all values
    duration = get_str(mp_duration_var)
    no_of_movements = get_int(mp_no_mov_var)
    duration_seconds = get_int(mp_dur_sec_var)
    duration_formatted = get_str(mp_dur_fmt_var)
    price = get_str(mp_price_var)  # text column, keep as str
    ismn = get_str(mp_ismn_var)
    is_duplicate = mp_is_dup_var.get()
    work_id = get_int(mp_work_id_var)
    not_difficult = mp_not_diff_var.get()
    rentable = mp_rentable_var.get()
    halstan_code = get_str(mp_halstan_var)
    composer = get_combo_str(mp_composer_var)
    librettist_1 = get_combo_str(mp_lib1_var)
    librettist_2 = get_combo_str(mp_lib2_var)
    media = get_combo_str(mp_media_var)
    sheet_music_plus_sku = get_str(mp_smp_sku_var)
    score_type = get_combo_str(mp_score_type_var)
    publication_year = get_int(mp_pub_year_var)
    isbn = get_str(mp_isbn_var)
    product_type = get_combo_str(mp_product_type_var)

    # Get selected categories
    selected_indices = category_listbox.curselection()
    selected_cats = [category_names[i] for i in selected_indices]

    try:
        conn = get_connection()
        cur = conn.cursor()

        # Update music_product
        cur.execute("""
            UPDATE public.music_product
            SET title = %s, duration = %s, no_of_movements = %s, duration_seconds = %s, duration_formatted = %s,
                price = %s, ismn = %s, is_duplicate = %s, work_id = %s, not_difficult = %s, rentable = %s, halstan_code = %s,
                composer = %s, librettist_1 = %s, librettist_2 = %s, media = %s, sheet_music_plus_sku = %s, score_type = %s,
                publication_year = %s, isbn = %s, product_type = %s
            WHERE product_id = %s;
        """, (title, duration, no_of_movements, duration_seconds, duration_formatted,
              price, ismn, is_duplicate, work_id, not_difficult, rentable, halstan_code,
              composer, librettist_1, librettist_2, media, sheet_music_plus_sku, score_type,
              publication_year, isbn, product_type, pid_val))

        if cur.rowcount == 0:
            messagebox.showerror("Error", f"No product with ID {pid_val} found to update.")
            conn.rollback()
            cur.close()
            conn.close()
            return

        # Update categories: delete old, insert new
        cur.execute("DELETE FROM public.product_category_junction WHERE product_id = %s;", (pid_val,))
        for cat_name in selected_cats:
            cat_id = category_ids[cat_name]
            cur.execute("""
                INSERT INTO public.product_category_junction (product_id, category_id)
                VALUES (%s, %s);
            """, (pid_val, cat_id))

        conn.commit()
        cur.close()
        conn.close()

        messagebox.showinfo("Success", f"Product {pid_val} updated successfully.")

    except Exception as e:
        messagebox.showerror("Database Error", f"Failed to update product:\n{e}")

def add_music_product():
    title = mp_title_var.get().strip()
    if not title:
        messagebox.showerror("Error", "Title is required.")
        return

    # Helper to get string or None
    def get_str(var):
        val = var.get().strip()
        return val if val else None

    # Helper to get int or None
    def get_int(var):
        val = var.get().strip()
        if not val:
            return None
        try:
            return int(val)
        except ValueError:
            messagebox.showerror("Error", f"Invalid integer: {val}")
            raise

    # Helper to get str for combo, handling "(None)"
    def get_combo_str(var):
        val = var.get().strip()
        return None if val == "(None)" or not val else val

    # Get all values
    duration = get_str(mp_duration_var)
    no_of_movements = get_int(mp_no_mov_var)
    duration_seconds = get_int(mp_dur_sec_var)
    duration_formatted = get_str(mp_dur_fmt_var)
    price = get_str(mp_price_var)  # text column, keep as str
    ismn = get_str(mp_ismn_var)
    is_duplicate = mp_is_dup_var.get()
    work_id = get_int(mp_work_id_var)
    not_difficult = mp_not_diff_var.get()
    rentable = mp_rentable_var.get()
    halstan_code = get_str(mp_halstan_var)
    composer = get_combo_str(mp_composer_var)
    librettist_1 = get_combo_str(mp_lib1_var)
    librettist_2 = get_combo_str(mp_lib2_var)
    media = get_combo_str(mp_media_var)
    sheet_music_plus_sku = get_str(mp_smp_sku_var)
    score_type = get_combo_str(mp_score_type_var)
    publication_year = get_int(mp_pub_year_var)
    isbn = get_str(mp_isbn_var)
    product_type = get_combo_str(mp_product_type_var)

    # Get selected categories
    selected_indices = category_listbox.curselection()
    selected_cats = [category_names[i] for i in selected_indices]

    try:
        conn = get_connection()
        cur = conn.cursor()

        # Get next product_id (since no sequence)
        cur.execute("SELECT COALESCE(MAX(product_id), 0) + 1 FROM public.music_product;")
        new_id = cur.fetchone()[0]

        # Insert into music_product
        cur.execute("""
            INSERT INTO public.music_product
                (product_id, title, duration, no_of_movements, duration_seconds, duration_formatted,
                 price, ismn, is_duplicate, work_id, not_difficult, rentable, halstan_code,
                 composer, librettist_1, librettist_2, media, sheet_music_plus_sku, score_type,
                 publication_year, isbn, product_type)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
        """, (new_id, title, duration, no_of_movements, duration_seconds, duration_formatted,
              price, ismn, is_duplicate, work_id, not_difficult, rentable, halstan_code,
              composer, librettist_1, librettist_2, media, sheet_music_plus_sku, score_type,
              publication_year, isbn, product_type))

        # Insert categories if selected
        for cat_name in selected_cats:
            cat_id = category_ids[cat_name]
            cur.execute("""
                INSERT INTO public.product_category_junction (product_id, category_id)
                VALUES (%s, %s);
            """, (new_id, cat_id))

        conn.commit()
        cur.close()
        conn.close()

        mp_product_id_display_var.set(str(new_id))
        messagebox.showinfo("Success", f"Product created!\nNew Product ID: {new_id}")

        # Optional: auto-fill into order tab
        product_id_var.set(str(new_id))
        if price:
            price_var.set(price)

        # Clear form after success (optional — comment out if unwanted)
        # clear_music_product_form()

    except Exception as e:
        messagebox.showerror("Database Error", f"Failed to add product:\n{e}")

def clear_music_product_form():
    mp_title_var.set("")
    mp_duration_var.set("")
    mp_no_mov_var.set("")
    mp_dur_sec_var.set("")
    mp_dur_fmt_var.set("")
    mp_price_var.set("")
    mp_ismn_var.set("")
    mp_is_dup_var.set(False)
    mp_work_id_var.set("")
    mp_not_diff_var.set(False)
    mp_rentable_var.set(False)
    mp_halstan_var.set("")
    mp_composer_var.set("(None)")
    mp_lib1_var.set("(None)")
    mp_lib2_var.set("(None)")
    mp_media_var.set("(None)")
    mp_smp_sku_var.set("")
    mp_score_type_var.set("(None)")
    mp_pub_year_var.set("")
    mp_isbn_var.set("")
    mp_product_type_var.set("(None)")
    mp_product_id_display_var.set("")
    mp_lookup_pid_var.set("")
    category_listbox.selection_clear(0, "end")


# =========================
# REPLENISH INVENTORY FUNCTIONS
# =========================

def check_product_id():
    pid = inv_prod_id_var.get().strip()
    if not pid:
        messagebox.showerror("Error", "Product ID is required.")
        return

    try:
        pid_val = int(pid)
    except ValueError:
        messagebox.showerror("Error", "Product ID must be an integer.")
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("SELECT title FROM public.music_product WHERE product_id = %s;", (pid_val,))
        row = cur.fetchone()
        cur.close()
        conn.close()

        if row:
            inv_title_display_var.set(row[0])
            messagebox.showinfo("Product Found", f"Title: {row[0]}")
        else:
            inv_title_display_var.set("")
            messagebox.showerror("Error", f"No product with ID {pid_val} found.")
    except Exception as e:
        messagebox.showerror("Database Error", f"Error checking product:\n{e}")

def replenish_inventory():
    global inv_last_action
    pid = inv_prod_id_var.get().strip()
    loc = inv_location_id_var.get().strip()
    qty = inv_qty_var.get().strip()
    bin_num = inv_bin_var.get().strip()
    rack_num = inv_rack_var.get().strip()
    h_code = inv_halstan_var.get().strip()

    if not pid or not loc or not qty:
        messagebox.showerror("Error", "Product ID, Location ID, and Quantity are required.")
        return

    if not inv_title_display_var.get():
        messagebox.showerror("Error", "Please check Product ID first.")
        return

    try:
        pid_val = int(pid)
        loc_val = int(loc)
        qty_val = int(qty)
    except ValueError:
        messagebox.showerror("Error", "Product ID, Location ID, and Quantity must be integers.")
        return

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO public.inventory
                (product_id, location_id, h_bin_num, h_rack_num, quantity, halstan_code)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (product_id, location_id) DO UPDATE
            SET
                h_bin_num = EXCLUDED.h_bin_num,
                h_rack_num = EXCLUDED.h_rack_num,
                quantity = public.inventory.quantity + EXCLUDED.quantity,
                halstan_code = COALESCE(EXCLUDED.halstan_code, public.inventory.halstan_code);
            """,
            (pid_val, loc_val, bin_num or None, rack_num or None, qty_val, h_code or None)
        )
        conn.commit()
        cur.close()
        conn.close()

        inv_last_action = (pid_val, loc_val, qty_val)  # Track for undo

        messagebox.showinfo("Inventory Replenished", "Inventory updated successfully.")
        # Do not clear form automatically; user can clear or undo
    except Exception as e:
        messagebox.showerror("Database Error", f"Error replenishing inventory:\n{e}")

def undo_replenish():
    global inv_last_action
    if not inv_last_action:
        messagebox.showerror("Error", "No recent action to undo.")
        return

    pid_val, loc_val, qty_val = inv_last_action
    undo_qty = -qty_val  # Negative to subtract

    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO public.inventory
                (product_id, location_id, quantity)
            VALUES (%s, %s, %s)
            ON CONFLICT (product_id, location_id) DO UPDATE
            SET quantity = public.inventory.quantity + EXCLUDED.quantity;
            """,
            (pid_val, loc_val, undo_qty)
        )
        conn.commit()
        cur.close()
        conn.close()

        inv_last_action = None  # Clear after undo
        messagebox.showinfo("Undo Successful", f"Reversed addition of {qty_val} for Product {pid_val} at Location {loc_val}.")
        clear_replenish_form()
    except Exception as e:
        messagebox.showerror("Database Error", f"Error undoing replenish:\n{e}")

def clear_replenish_form():
    inv_prod_id_var.set("")
    inv_location_id_var.set("1")
    inv_qty_var.set("")
    inv_bin_var.set("")
    inv_rack_var.set("")
    inv_halstan_var.set("")
    inv_title_display_var.set("")


# =========================
# MAIN GUI
# =========================

root = tk.Tk()
root.title("Wiscasset Music Database - Orders, Customers, Catalog")

notebook = ttk.Notebook(root)
notebook.pack(fill="both", expand=True, padx=10, pady=10)

# ---------- Orders Tab ----------
order_frame = ttk.Frame(notebook, padding=10)
notebook.add(order_frame, text="Orders")

customer_id_var = tk.StringVar()
order_id_var = tk.StringVar()
product_id_var = tk.StringVar()
quantity_var = tk.StringVar(value="1")
price_var = tk.StringVar()
location_id_var = tk.StringVar(value="1")  # default location

ttk.Label(order_frame, text="Customer ID:").grid(column=0, row=0, sticky="e")
ttk.Entry(order_frame, textvariable=customer_id_var, width=10).grid(column=1, row=0, sticky="w")

ttk.Button(order_frame, text="Create Order", command=create_order).grid(column=2, row=0, padx=5, sticky="w")

ttk.Label(order_frame, text="Order ID:").grid(column=0, row=1, sticky="e")
ttk.Entry(order_frame, textvariable=order_id_var, width=10).grid(column=1, row=1, sticky="w")

ttk.Label(order_frame, text="Product ID:").grid(column=0, row=2, sticky="e")
ttk.Entry(order_frame, textvariable=product_id_var, width=10).grid(column=1, row=2, sticky="w")

ttk.Label(order_frame, text="Quantity:").grid(column=0, row=3, sticky="e")
ttk.Entry(order_frame, textvariable=quantity_var, width=10).grid(column=1, row=3, sticky="w")

ttk.Label(order_frame, text="Unit Price:").grid(column=0, row=4, sticky="e")
ttk.Entry(order_frame, textvariable=price_var, width=10).grid(column=1, row=4, sticky="w")

ttk.Label(order_frame, text="Fulfilled From Location ID:").grid(column=0, row=5, sticky="e")
ttk.Entry(order_frame, textvariable=location_id_var, width=10).grid(column=1, row=5, sticky="w")

ttk.Button(order_frame, text="Add Line", command=add_order_line).grid(column=2, row=5, padx=5, sticky="w")
ttk.Button(order_frame, text="View Invoice", command=show_invoice).grid(column=2, row=6, padx=5, sticky="w")

# Order lines Treeview
order_lines_columns = ("line_id", "product_id", "title", "qty", "price", "total")
order_lines_tree = ttk.Treeview(order_frame, columns=order_lines_columns, show="headings", height=10)
headings = ["Line ID", "Product ID", "Title", "Qty", "Price", "Total"]
for col, text in zip(order_lines_columns, headings):
    order_lines_tree.heading(col, text=text)
    if col == "title":
        order_lines_tree.column(col, width=260)
    else:
        order_lines_tree.column(col, width=90)
order_lines_tree.grid(column=0, row=7, columnspan=3, pady=10, sticky="nsew")
order_frame.rowconfigure(7, weight=1)
order_frame.columnconfigure(2, weight=1)

# ---------- Customers Tab ----------
customer_frame = ttk.Frame(notebook, padding=10)
notebook.add(customer_frame, text="Customers")

cust_first_name_var = tk.StringVar()
cust_last_name_var = tk.StringVar()
cust_email_var = tk.StringVar()
cust_phone_var = tk.StringVar()
cust_street_var = tk.StringVar()
cust_town_var = tk.StringVar()
cust_zip_var = tk.StringVar()
cust_country_var = tk.StringVar()
cust_lookup_id_var = tk.StringVar()

row = 0
ttk.Label(customer_frame, text="Lookup Customer ID:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_lookup_id_var, width=10).grid(column=1, row=row, sticky="w")
ttk.Button(customer_frame, text="Load", command=load_customer).grid(column=2, row=row, sticky="w", padx=5)

row += 1
ttk.Label(customer_frame, text="First Name:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_first_name_var, width=30).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(customer_frame, text="Last Name:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_last_name_var, width=30).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(customer_frame, text="Email:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_email_var, width=40).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(customer_frame, text="Phone:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_phone_var, width=20).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(customer_frame, text="Street Address:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_street_var, width=40).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(customer_frame, text="Town/City:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_town_var, width=30).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(customer_frame, text="ZIP/Postal Code:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_zip_var, width=15).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(customer_frame, text="Country:").grid(column=0, row=row, sticky="e")
ttk.Entry(customer_frame, textvariable=cust_country_var, width=30).grid(column=1, row=row, sticky="w")

row += 1
ttk.Button(customer_frame, text="Save Customer", command=save_customer).grid(column=1, row=row, sticky="w", pady=10)
ttk.Button(customer_frame, text="Clear", command=clear_customer_form).grid(column=1, row=row, sticky="e", pady=10)

# ---------- Product Search Tab ----------
search_frame = ttk.Frame(notebook, padding=10)
notebook.add(search_frame, text="Product Search")

ttk.Label(search_frame, text="Welcome to Wiscasset Music – the source for sheet music composed by B. Warren")\
    .grid(column=0, row=0, columnspan=3, sticky="w", pady=(0, 10))

search_category_var = tk.StringVar()
search_composer_var = tk.StringVar()
search_media_var = tk.StringVar()
search_product_type_var = tk.StringVar()

ttk.Label(search_frame, text="Q1. Category:").grid(column=0, row=1, sticky="e")
search_category_combo = ttk.Combobox(search_frame, textvariable=search_category_var, width=30, state="readonly")
search_category_combo.grid(column=1, row=1, sticky="w")

ttk.Label(search_frame, text="Q2. Composer:").grid(column=0, row=2, sticky="e")
search_composer_combo = ttk.Combobox(search_frame, textvariable=search_composer_var, width=30, state="readonly")
search_composer_combo.grid(column=1, row=2, sticky="w")

ttk.Label(search_frame, text="Q3. Media:").grid(column=0, row=3, sticky="e")
search_media_combo = ttk.Combobox(search_frame, textvariable=search_media_var, width=30, state="readonly")
search_media_combo.grid(column=1, row=3, sticky="w")

ttk.Label(search_frame, text="Q4. Product Type:").grid(column=0, row=4, sticky="e")
search_product_type_combo = ttk.Combobox(search_frame, textvariable=search_product_type_var, width=30, state="readonly")
search_product_type_combo.grid(column=1, row=4, sticky="w")

ttk.Button(search_frame, text="Search", command=run_product_search).grid(column=1, row=5, sticky="w", pady=5)
ttk.Button(search_frame, text="Clear Search", command=clear_product_search).grid(column=2, row=5, sticky="w", pady=5)

# Results tree with inventory qty
columns = ("product_id", "title", "composer", "media", "product_type", "price", "qty")
product_tree = ttk.Treeview(search_frame, columns=columns, show="headings", height=12)
for col, text in zip(
    columns,
    ["Product ID", "Title", "Composer", "Media", "Product Type", "Price", "Qty in Inv."]
):
    product_tree.heading(col, text=text)
    if col == "title":
        product_tree.column(col, width=260)
    else:
        product_tree.column(col, width=100)

product_tree.grid(column=0, row=6, columnspan=3, pady=10, sticky="nsew")
search_frame.rowconfigure(6, weight=1)
search_frame.columnconfigure(2, weight=1)

ttk.Button(search_frame, text="Use Selected for Order", command=use_selected_product_for_order)\
    .grid(column=1, row=7, sticky="w", pady=5)

# ---------- Add Music Product Tab ----------
mp_frame = ttk.Frame(notebook, padding=10)
notebook.add(mp_frame, text="Add Music Product")

# Variables for all music_product fields
mp_title_var = tk.StringVar()
mp_duration_var = tk.StringVar()
mp_no_mov_var = tk.StringVar()
mp_dur_sec_var = tk.StringVar()
mp_dur_fmt_var = tk.StringVar()
mp_price_var = tk.StringVar()
mp_ismn_var = tk.StringVar()
mp_is_dup_var = tk.BooleanVar(value=False)
mp_work_id_var = tk.StringVar()
mp_not_diff_var = tk.BooleanVar(value=False)
mp_rentable_var = tk.BooleanVar(value=False)
mp_halstan_var = tk.StringVar()
mp_composer_var = tk.StringVar()
mp_lib1_var = tk.StringVar()
mp_lib2_var = tk.StringVar()
mp_media_var = tk.StringVar()
mp_smp_sku_var = tk.StringVar()
mp_score_type_var = tk.StringVar()
mp_pub_year_var = tk.StringVar()
mp_isbn_var = tk.StringVar()
mp_product_type_var = tk.StringVar()
mp_product_id_display_var = tk.StringVar()
mp_lookup_pid_var = tk.StringVar()  # New for lookup

# For categories (multi-select listbox)
category_names = []  # Will load names
category_ids = {}    # name -> id

# Load dropdown options and categories (extended from search tab)
def load_add_product_filters():
    global category_names, category_ids
    try:
        conn = get_connection()
        cur = conn.cursor()

        # Categories (for multi-select)
        cur.execute("SELECT category_id, category_name FROM public.category ORDER BY category_name;")
        cats = cur.fetchall()
        category_names = [row[1] for row in cats]
        category_ids = {row[1]: row[0] for row in cats}
        category_listbox.delete(0, "end")
        for name in category_names:
            category_listbox.insert("end", name)

        # Composer
        cur.execute("SELECT DISTINCT composer FROM public.music_product WHERE composer IS NOT NULL ORDER BY composer;")
        composers = [r[0] for r in cur.fetchall()]
        mp_composer_combo["values"] = ["(None)"] + composers
        if "B. Warren" in composers:
            mp_composer_var.set("B. Warren")
        elif composers:
            mp_composer_var.set(composers[0])
        else:
            mp_composer_var.set("(None)")

        # Librettist 1
        cur.execute("SELECT DISTINCT librettist_1 FROM public.music_product WHERE librettist_1 IS NOT NULL ORDER BY librettist_1;")
        lib1s = [r[0] for r in cur.fetchall()]
        mp_lib1_combo["values"] = ["(None)"] + lib1s
        mp_lib1_var.set("(None)")

        # Librettist 2
        cur.execute("SELECT DISTINCT librettist_2 FROM public.music_product WHERE librettist_2 IS NOT NULL ORDER BY librettist_2;")
        lib2s = [r[0] for r in cur.fetchall()]
        mp_lib2_combo["values"] = ["(None)"] + lib2s
        mp_lib2_var.set("(None)")

        # Media
        cur.execute("SELECT DISTINCT media FROM public.music_product WHERE media IS NOT NULL ORDER BY media;")
        medias = [r[0] for r in cur.fetchall()]
        media_vals = ["(None)"] + medias
        mp_media_combo["values"] = media_vals
        if "print" in medias:
            mp_media_var.set("print")
        else:
            mp_media_var.set("(None)")

        # Product Type
        cur.execute("SELECT DISTINCT product_type FROM public.music_product WHERE product_type IS NOT NULL ORDER BY product_type;")
        ptypes = [r[0] for r in cur.fetchall()]
        ptype_vals = ["(None)"] + ptypes
        mp_product_type_combo["values"] = ptype_vals
        if "Sheet Music" in ptypes:
            mp_product_type_var.set("Sheet Music")
        else:
            mp_product_type_var.set("(None)")

        # Score Type
        cur.execute("SELECT DISTINCT score_type FROM public.music_product WHERE score_type IS NOT NULL ORDER BY score_type;")
        scores = [r[0] for r in cur.fetchall()]
        score_vals = ["(None)"] + scores
        mp_score_type_combo["values"] = score_vals
        mp_score_type_var.set("(None)")

        cur.close()
        conn.close()
    except Exception as e:
        messagebox.showerror("DB Error", f"Could not load dropdowns:\n{e}")

# GUI Layout
row = 0
ttk.Label(mp_frame, text="Lookup Product ID:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_lookup_pid_var, width=10).grid(column=1, row=row, sticky="w")
ttk.Button(mp_frame, text="Load Product", command=load_music_product).grid(column=2, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Title:", font=("", 10, "bold")).grid(column=0, row=row, sticky="e", pady=4)
ttk.Entry(mp_frame, textvariable=mp_title_var, width=50).grid(column=1, row=row, columnspan=2, sticky="w", pady=4, padx=5)

row += 1
ttk.Label(mp_frame, text="Q1. Composer:").grid(column=0, row=row, sticky="e")
mp_composer_combo = ttk.Combobox(mp_frame, textvariable=mp_composer_var, width=30, state="readonly")
mp_composer_combo.grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Q2. Media:").grid(column=0, row=row, sticky="e")
mp_media_combo = ttk.Combobox(mp_frame, textvariable=mp_media_var, width=30, state="readonly")
mp_media_combo.grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Q3. Product Type:").grid(column=0, row=row, sticky="e")
mp_product_type_combo = ttk.Combobox(mp_frame, textvariable=mp_product_type_var, width=30, state="readonly")
mp_product_type_combo.grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Q4. Categories (multi-select):").grid(column=0, row=row, sticky="ne", pady=4)
category_listbox = tk.Listbox(mp_frame, selectmode="multiple", height=6, width=32)
category_listbox.grid(column=1, row=row, sticky="w", padx=5, pady=4)

row += 1
ttk.Label(mp_frame, text="Duration:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_duration_var, width=30).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="No. of Movements:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_no_mov_var, width=10).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Duration (seconds):").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_dur_sec_var, width=10).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Duration Formatted:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_dur_fmt_var, width=30).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Price:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_price_var, width=12).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="ISMN:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_ismn_var, width=20).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Checkbutton(mp_frame, text="Is Duplicate", variable=mp_is_dup_var).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Work ID:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_work_id_var, width=10).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Checkbutton(mp_frame, text="Not Difficult", variable=mp_not_diff_var).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Checkbutton(mp_frame, text="Rentable", variable=mp_rentable_var).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Halstan Code:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_halstan_var, width=15).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Librettist 1:").grid(column=0, row=row, sticky="e")
mp_lib1_combo = ttk.Combobox(mp_frame, textvariable=mp_lib1_var, width=30, state="readonly")
mp_lib1_combo.grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Librettist 2:").grid(column=0, row=row, sticky="e")
mp_lib2_combo = ttk.Combobox(mp_frame, textvariable=mp_lib2_var, width=30, state="readonly")
mp_lib2_combo.grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Sheet Music Plus SKU:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_smp_sku_var, width=20).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Score Type:").grid(column=0, row=row, sticky="e")
mp_score_type_combo = ttk.Combobox(mp_frame, textvariable=mp_score_type_var, width=30, state="readonly")
mp_score_type_combo.grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="Publication Year:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_pub_year_var, width=8).grid(column=1, row=row, sticky="w", padx=5)

row += 1
ttk.Label(mp_frame, text="ISBN:").grid(column=0, row=row, sticky="e")
ttk.Entry(mp_frame, textvariable=mp_isbn_var, width=20).grid(column=1, row=row, sticky="w", padx=5)

# Buttons and result
row += 1
button_frame = ttk.Frame(mp_frame)
button_frame.grid(column=0, row=row, columnspan=3, pady=15)

ttk.Button(button_frame, text="Add Music Product", command=add_music_product).pack(side="left", padx=10)
ttk.Button(button_frame, text="Update Product", command=update_music_product).pack(side="left", padx=10)
ttk.Button(button_frame, text="Clear Form", command=clear_music_product_form).pack(side="left", padx=10)

row += 1
ttk.Label(mp_frame, text="Product ID:", font=("", 10, "bold")).grid(column=0, row=row, sticky="e", pady=8)
ttk.Label(mp_frame, textvariable=mp_product_id_display_var, font=("", 12, "bold"), foreground="green")\
    .grid(column=1, row=row, sticky="w", padx=5)

# Load defaults when tab is created
load_add_product_filters()

# ---------- Replenish Inventory Tab ----------
inv_frame = ttk.Frame(notebook, padding=10)
notebook.add(inv_frame, text="Replenish Inventory")

inv_prod_id_var = tk.StringVar()
inv_location_id_var = tk.StringVar(value="1")
inv_qty_var = tk.StringVar()
inv_bin_var = tk.StringVar()
inv_rack_var = tk.StringVar()
inv_halstan_var = tk.StringVar()
inv_title_display_var = tk.StringVar(value="")  # To display title after check
inv_last_action = None  # To track last replenish for undo (product_id, location_id, qty_added)

row = 0
ttk.Label(inv_frame, text="Product ID:").grid(column=0, row=row, sticky="e")
ttk.Entry(inv_frame, textvariable=inv_prod_id_var, width=10).grid(column=1, row=row, sticky="w")
ttk.Button(inv_frame, text="Check Product ID", command=check_product_id).grid(column=2, row=row, sticky="w", padx=5)

row += 1
ttk.Label(inv_frame, text="Product Title:").grid(column=0, row=row, sticky="e")
ttk.Label(inv_frame, textvariable=inv_title_display_var, width=40).grid(column=1, row=row, columnspan=2, sticky="w")

row += 1
ttk.Label(inv_frame, text="Location ID:").grid(column=0, row=row, sticky="e")
ttk.Entry(inv_frame, textvariable=inv_location_id_var, width=10).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(inv_frame, text="Quantity to Add:").grid(column=0, row=row, sticky="e")
ttk.Entry(inv_frame, textvariable=inv_qty_var, width=10).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(inv_frame, text="Bin:").grid(column=0, row=row, sticky="e")
ttk.Entry(inv_frame, textvariable=inv_bin_var, width=15).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(inv_frame, text="Rack:").grid(column=0, row=row, sticky="e")
ttk.Entry(inv_frame, textvariable=inv_rack_var, width=15).grid(column=1, row=row, sticky="w")

row += 1
ttk.Label(inv_frame, text="Halstan Code:").grid(column=0, row=row, sticky="e")
ttk.Entry(inv_frame, textvariable=inv_halstan_var, width=15).grid(column=1, row=row, sticky="w")

row += 1
button_frame = ttk.Frame(inv_frame)
button_frame.grid(column=1, row=row, columnspan=2, pady=10, sticky="w")
ttk.Button(button_frame, text="Replenish", command=replenish_inventory).pack(side="left", padx=5)
ttk.Button(button_frame, text="Undo Last", command=undo_replenish).pack(side="left", padx=5)
ttk.Button(button_frame, text="Clear", command=clear_replenish_form).pack(side="right", padx=5)

# Load filter options for product search
load_filter_options()

root.mainloop()
