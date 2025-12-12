--
-- PostgreSQL database dump
--

\restrict GRH4bAHtjEqpEKoIL6LLy0Y6MsfU8psxYi9WCc8MgjaPjTvbFJ0VnygIWimRlA7

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

-- Started on 2025-12-11 23:35:59 EST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 239 (class 1255 OID 41768)
-- Name: order_line_inventory_movement(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.order_line_inventory_movement() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_location_id int;
    v_product_id int;
    v_old_qty int;
    v_new_qty int;
    v_delta int;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_location_id := NEW.fulfilled_from_location_id;
        v_product_id  := NEW.product_id;
        v_old_qty     := 0;
        v_new_qty     := NEW.quantity;
    ELSIF TG_OP = 'UPDATE' THEN
        v_location_id := COALESCE(NEW.fulfilled_from_location_id, OLD.fulfilled_from_location_id);
        v_product_id  := COALESCE(NEW.product_id, OLD.product_id);
        v_old_qty     := COALESCE(OLD.quantity, 0);
        v_new_qty     := COALESCE(NEW.quantity, 0);
    ELSIF TG_OP = 'DELETE' THEN
        v_location_id := OLD.fulfilled_from_location_id;
        v_product_id  := OLD.product_id;
        v_old_qty     := OLD.quantity;
        v_new_qty     := 0;
    END IF;

    v_delta := v_new_qty - v_old_qty;

    -- If no location, do nothing
    IF v_location_id IS NULL OR v_product_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- 1) Update inventory table (accumulate style)
    -- If no row exists yet for this (product, location), create one.
    INSERT INTO public.inventory (product_id, location_id, quantity)
    VALUES (v_product_id, v_location_id, -v_delta)
    ON CONFLICT (product_id, location_id)
    DO UPDATE
       SET quantity = public.inventory.quantity - v_delta;

    -- 2) Log in inventory_movement
    IF v_delta <> 0 THEN
        INSERT INTO public.inventory_movement (
            product_id,
            from_location_id,
            to_location_id,
            quantity,
            movement_type,
            reference
        )
        VALUES (
            v_product_id,
            v_location_id,
            NULL,
            ABS(v_delta),
            CASE
                WHEN TG_OP = 'INSERT' AND v_delta > 0 THEN 'sale'
                WHEN TG_OP = 'UPDATE' AND v_delta > 0 THEN 'sale_adjust_increase'
                WHEN TG_OP = 'UPDATE' AND v_delta < 0 THEN 'sale_adjust_decrease'
                WHEN TG_OP = 'DELETE' THEN 'sale_cancel'
                ELSE 'sale'
            END,
            CONCAT('order ', COALESCE(NEW.order_id, OLD.order_id))
        );
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 229 (class 1259 OID 41676)
-- Name: category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.category (
    category_id integer NOT NULL,
    category_name character varying(100)
);


--
-- TOC entry 228 (class 1259 OID 41675)
-- Name: category_category_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.category_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3844 (class 0 OID 0)
-- Dependencies: 228
-- Name: category_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.category_category_id_seq OWNED BY public.category.category_id;


--
-- TOC entry 218 (class 1259 OID 34132)
-- Name: customer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer (
    customer_id integer NOT NULL,
    first_name character varying(100),
    last_name character varying(100),
    email_addr character varying(255),
    phone character varying(20),
    street_address character varying(255),
    town character varying(100),
    zip character varying(20),
    country character varying(100)
);


--
-- TOC entry 217 (class 1259 OID 34131)
-- Name: customer_customer_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customer_customer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3845 (class 0 OID 0)
-- Dependencies: 217
-- Name: customer_customer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customer_customer_id_seq OWNED BY public.customer.customer_id;


--
-- TOC entry 222 (class 1259 OID 34191)
-- Name: order_line; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_line (
    order_line_id integer NOT NULL,
    order_id integer NOT NULL,
    product_id integer NOT NULL,
    product_price numeric(10,2) NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    fulfilled_from_location_id integer,
    line_total numeric(10,2) GENERATED ALWAYS AS ((product_price * (quantity)::numeric)) STORED
);


--
-- TOC entry 220 (class 1259 OID 34164)
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    order_id integer NOT NULL,
    order_date date,
    customer_id integer,
    inv_pull_date date,
    billing_address text,
    billing_country character varying(100),
    billing_street character varying(255),
    billing_zip character varying(20)
);


--
-- TOC entry 235 (class 1259 OID 41758)
-- Name: customer_order_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.customer_order_summary AS
 SELECT c.customer_id,
    c.first_name,
    c.last_name,
    count(DISTINCT o.order_id) AS order_count,
    COALESCE(sum(ol.line_total), (0)::numeric) AS total_spent
   FROM ((public.customer c
     LEFT JOIN public.orders o ON ((o.customer_id = c.customer_id)))
     LEFT JOIN public.order_line ol ON ((ol.order_id = o.order_id)))
  GROUP BY c.customer_id, c.first_name, c.last_name;


--
-- TOC entry 224 (class 1259 OID 34252)
-- Name: inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory (
    inventory_id integer NOT NULL,
    product_id integer NOT NULL,
    location_id integer NOT NULL,
    h_bin_num character varying(50),
    h_rack_num character varying(50),
    quantity integer DEFAULT 0 NOT NULL,
    parcel_qty integer,
    halstan_code character varying(10)
);


--
-- TOC entry 227 (class 1259 OID 34326)
-- Name: inventory_halstan_staging; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_halstan_staging (
    title_raw text,
    halstan_code text,
    quantity integer,
    parcel_qty integer,
    h_bin_num character varying(50),
    rack_num text,
    staging_id integer NOT NULL,
    product_id integer
);


--
-- TOC entry 233 (class 1259 OID 41717)
-- Name: inventory_halstan_staging_staging_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_halstan_staging_staging_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3846 (class 0 OID 0)
-- Dependencies: 233
-- Name: inventory_halstan_staging_staging_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_halstan_staging_staging_id_seq OWNED BY public.inventory_halstan_staging.staging_id;


--
-- TOC entry 223 (class 1259 OID 34251)
-- Name: inventory_inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_inventory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3847 (class 0 OID 0)
-- Dependencies: 223
-- Name: inventory_inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_inventory_id_seq OWNED BY public.inventory.inventory_id;


--
-- TOC entry 238 (class 1259 OID 41771)
-- Name: inventory_movement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_movement (
    movement_id integer NOT NULL,
    product_id integer NOT NULL,
    from_location_id integer,
    to_location_id integer,
    quantity integer NOT NULL,
    movement_type character varying(30) NOT NULL,
    movement_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    reference text
);


--
-- TOC entry 237 (class 1259 OID 41770)
-- Name: inventory_movement_movement_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_movement_movement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3848 (class 0 OID 0)
-- Dependencies: 237
-- Name: inventory_movement_movement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_movement_movement_id_seq OWNED BY public.inventory_movement.movement_id;


--
-- TOC entry 226 (class 1259 OID 34272)
-- Name: location; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.location (
    location_id integer NOT NULL,
    location_name character varying(50) NOT NULL
);


--
-- TOC entry 230 (class 1259 OID 41684)
-- Name: music_product; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.music_product (
    product_id integer NOT NULL,
    title text NOT NULL,
    duration text,
    no_of_movements integer,
    duration_seconds integer,
    duration_formatted text,
    price text,
    ismn text,
    is_duplicate boolean,
    work_id integer,
    not_difficult boolean,
    rentable boolean,
    halstan_code text,
    composer text,
    librettist_1 text,
    librettist_2 text,
    media text,
    sheet_music_plus_sku text,
    score_type text,
    publication_year integer,
    isbn character varying(13),
    product_type text
);


--
-- TOC entry 236 (class 1259 OID 41763)
-- Name: inventory_with_location; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.inventory_with_location AS
 SELECT i.inventory_id,
    i.product_id,
    mp.title,
    i.location_id,
    l.location_name,
    i.quantity,
    i.h_bin_num,
    i.h_rack_num,
    i.halstan_code
   FROM ((public.inventory i
     JOIN public.music_product mp ON ((mp.product_id = i.product_id)))
     JOIN public.location l ON ((l.location_id = i.location_id)));


--
-- TOC entry 225 (class 1259 OID 34271)
-- Name: location_location_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.location_location_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3849 (class 0 OID 0)
-- Dependencies: 225
-- Name: location_location_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.location_location_id_seq OWNED BY public.location.location_id;


--
-- TOC entry 231 (class 1259 OID 41691)
-- Name: product_category_junction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_category_junction (
    product_id integer NOT NULL,
    category_id integer NOT NULL
);


--
-- TOC entry 232 (class 1259 OID 41706)
-- Name: music_product_with_primary_category; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.music_product_with_primary_category AS
 SELECT DISTINCT ON (mp.product_id) mp.product_id,
    mp.title,
    mp.duration,
    mp.no_of_movements,
    mp.duration_seconds,
    mp.duration_formatted,
    mp.price,
    mp.ismn,
    mp.is_duplicate,
    mp.work_id,
    mp.not_difficult,
    mp.rentable,
    mp.halstan_code,
    mp.composer,
    mp.librettist_1,
    mp.librettist_2,
    mp.media,
    mp.sheet_music_plus_sku,
    mp.score_type,
    mp.publication_year,
    pc.category_id AS primary_category_id
   FROM ((public.music_product mp
     JOIN public.product_category_junction pc ON ((mp.product_id = pc.product_id)))
     JOIN public.category c ON ((pc.category_id = c.category_id)))
  ORDER BY mp.product_id,
        CASE pc.category_id
            WHEN 4 THEN 1
            WHEN 5 THEN 2
            WHEN 3 THEN 3
            WHEN 1 THEN 4
            WHEN 2 THEN 5
            ELSE 99
        END;


--
-- TOC entry 221 (class 1259 OID 34190)
-- Name: order_line_order_line_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.order_line_order_line_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3850 (class 0 OID 0)
-- Dependencies: 221
-- Name: order_line_order_line_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.order_line_order_line_id_seq OWNED BY public.order_line.order_line_id;


--
-- TOC entry 219 (class 1259 OID 34163)
-- Name: orders_order_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.orders_order_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 3851 (class 0 OID 0)
-- Dependencies: 219
-- Name: orders_order_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.orders_order_id_seq OWNED BY public.orders.order_id;


--
-- TOC entry 234 (class 1259 OID 41753)
-- Name: orders_with_total; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.orders_with_total AS
 SELECT o.order_id,
    o.order_date,
    o.customer_id,
    o.inv_pull_date,
    o.billing_address,
    o.billing_country,
    o.billing_street,
    o.billing_zip,
    COALESCE(sum(ol.line_total), (0)::numeric) AS order_total
   FROM (public.orders o
     LEFT JOIN public.order_line ol ON ((ol.order_id = o.order_id)))
  GROUP BY o.order_id, o.order_date, o.customer_id, o.inv_pull_date, o.billing_address, o.billing_country, o.billing_street, o.billing_zip;


--
-- TOC entry 3626 (class 2604 OID 41679)
-- Name: category category_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.category ALTER COLUMN category_id SET DEFAULT nextval('public.category_category_id_seq'::regclass);


--
-- TOC entry 3617 (class 2604 OID 34135)
-- Name: customer customer_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer ALTER COLUMN customer_id SET DEFAULT nextval('public.customer_customer_id_seq'::regclass);


--
-- TOC entry 3622 (class 2604 OID 34255)
-- Name: inventory inventory_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory ALTER COLUMN inventory_id SET DEFAULT nextval('public.inventory_inventory_id_seq'::regclass);


--
-- TOC entry 3625 (class 2604 OID 41718)
-- Name: inventory_halstan_staging staging_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_halstan_staging ALTER COLUMN staging_id SET DEFAULT nextval('public.inventory_halstan_staging_staging_id_seq'::regclass);


--
-- TOC entry 3627 (class 2604 OID 41774)
-- Name: inventory_movement movement_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movement ALTER COLUMN movement_id SET DEFAULT nextval('public.inventory_movement_movement_id_seq'::regclass);


--
-- TOC entry 3624 (class 2604 OID 34275)
-- Name: location location_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location ALTER COLUMN location_id SET DEFAULT nextval('public.location_location_id_seq'::regclass);


--
-- TOC entry 3619 (class 2604 OID 34194)
-- Name: order_line order_line_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_line ALTER COLUMN order_line_id SET DEFAULT nextval('public.order_line_order_line_id_seq'::regclass);


--
-- TOC entry 3618 (class 2604 OID 34167)
-- Name: orders order_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders ALTER COLUMN order_id SET DEFAULT nextval('public.orders_order_id_seq'::regclass);


--
-- TOC entry 3833 (class 0 OID 41676)
-- Dependencies: 229
-- Data for Name: category; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.category VALUES (1, 'Winds');
INSERT INTO public.category VALUES (2, 'Keyboard');
INSERT INTO public.category VALUES (3, 'Strings');
INSERT INTO public.category VALUES (4, 'Opera');
INSERT INTO public.category VALUES (5, 'Orchestral and Chamber works');
INSERT INTO public.category VALUES (6, 'Other');


--
-- TOC entry 3822 (class 0 OID 34132)
-- Dependencies: 218
-- Data for Name: customer; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.customer VALUES (1, 'Citizen', 'Kane', 'Orson@Wells.com', '(207) 555-1212', '123 Any Street', 'Anytown, ME', '02123', 'USA');
INSERT INTO public.customer VALUES (2, 'Bugs', 'Bunny', 'Bugs@WB.com', '(808) 555-1212', '123 Mainly Street', 'Paris, ME', '02124', 'USA');
INSERT INTO public.customer VALUES (3, 'Elmer', 'Fudd', 'Wabbits@WB.com', '(202) 555-1212', '123 Santa Monica Blvd', 'Beverly Hills, CA', '90210', 'USA');
INSERT INTO public.customer VALUES (4, 'Daffy', 'Duck', 'daffy@wb.com', '305-123-4567', '9001 Wilshire Blvd', 'Santa Monica, CA', '91638', 'USA');
INSERT INTO public.customer VALUES (5, 'Wyle E', 'Coyote', 'desert@wb.com', '808-555-1212', 'street', 'Reno, NV', '', 'USA');


--
-- TOC entry 3828 (class 0 OID 34252)
-- Dependencies: 224
-- Data for Name: inventory; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.inventory VALUES (21, 87, 1, '3', NULL, 20, 1, 'W1 26');
INSERT INTO public.inventory VALUES (22, 74, 1, '3', NULL, 18, 1, 'W1 23');
INSERT INTO public.inventory VALUES (24, 41, 1, 'RACK B7', NULL, 247, 2, 'W1 32');
INSERT INTO public.inventory VALUES (25, 40, 1, NULL, NULL, 0, NULL, 'W1 39');
INSERT INTO public.inventory VALUES (27, 53, 1, '4', NULL, 25, 1, 'W1 66');
INSERT INTO public.inventory VALUES (28, 63, 1, '4', NULL, 93, 1, 'W1 62');
INSERT INTO public.inventory VALUES (29, 10, 1, '1', NULL, 87, 1, 'W1 05');
INSERT INTO public.inventory VALUES (30, 15, 1, NULL, NULL, 0, 0, 'W1 04');
INSERT INTO public.inventory VALUES (31, 6, 1, '2', NULL, 71, 1, 'W1 13');
INSERT INTO public.inventory VALUES (32, 86, 1, '3', NULL, 20, 1, 'W1 25');
INSERT INTO public.inventory VALUES (33, 26, 1, '4', NULL, 90, 2, 'W1 64');
INSERT INTO public.inventory VALUES (34, 12, 1, '4', NULL, 169, 4, 'W1 69');
INSERT INTO public.inventory VALUES (35, 85, 1, '3', NULL, 25, 1, 'W1 24');
INSERT INTO public.inventory VALUES (37, 39, 1, '4', NULL, 170, 1, 'W1 72');
INSERT INTO public.inventory VALUES (38, 24, 1, '1', NULL, 78, 1, 'W1 01');
INSERT INTO public.inventory VALUES (39, 19, 1, NULL, NULL, 0, NULL, 'W1 40');
INSERT INTO public.inventory VALUES (40, 89, 1, '4', NULL, 110, 2, 'W1 74');
INSERT INTO public.inventory VALUES (42, 36, 1, '3', NULL, 322, 2, 'W1 27');
INSERT INTO public.inventory VALUES (44, 21, 1, '3', NULL, 130, 1, 'W1 36');
INSERT INTO public.inventory VALUES (46, 3, 1, '1', NULL, 68, 1, 'W1 06');
INSERT INTO public.inventory VALUES (47, 22, 1, '3', NULL, 30, 1, 'W1 17');
INSERT INTO public.inventory VALUES (48, 20, 1, NULL, NULL, 0, NULL, 'W1 38');
INSERT INTO public.inventory VALUES (52, 5, 1, '2', NULL, 17, 1, 'W1 10');
INSERT INTO public.inventory VALUES (53, 18, 1, '4', NULL, 290, 12, 'W1 77');
INSERT INTO public.inventory VALUES (54, 64, 1, '3', NULL, 235, 3, 'W1 28');
INSERT INTO public.inventory VALUES (55, 2, 1, '4', NULL, 50, 4, 'W1 75');
INSERT INTO public.inventory VALUES (56, 55, 1, '3', NULL, 60, 1, 'W1 47');
INSERT INTO public.inventory VALUES (57, 27, 1, '4', NULL, 35, 1, 'W1 70');
INSERT INTO public.inventory VALUES (58, 23, 1, '3', NULL, 150, 1, 'W1 35');
INSERT INTO public.inventory VALUES (60, 58, 1, '4', NULL, 163, 4, 'W1 73');
INSERT INTO public.inventory VALUES (49, 59, 1, '1', NULL, 69, 1, 'W1 02');
INSERT INTO public.inventory VALUES (50, 76, 1, '4', NULL, 304, 7, 'W1 83');
INSERT INTO public.inventory VALUES (61, 44, 1, '3', NULL, 171, 3, 'W1 42');
INSERT INTO public.inventory VALUES (23, 54, 1, '3', NULL, 56, 1, 'W1 49');
INSERT INTO public.inventory VALUES (75, 91, 2, '77', 'R TEST', 1, NULL, 'H TEST');
INSERT INTO public.inventory VALUES (51, 65, 1, '3', NULL, 184, 1, 'W1 54');
INSERT INTO public.inventory VALUES (59, 91, 1, '2', 'RACK B7', 514, 55, 'W1 12');
INSERT INTO public.inventory VALUES (43, 31, 1, '3', NULL, 96, 1, 'W1 16');
INSERT INTO public.inventory VALUES (26, 52, 1, '1', NULL, 98, 1, 'W1 03');
INSERT INTO public.inventory VALUES (81, 48, 1, NULL, NULL, -1, NULL, NULL);
INSERT INTO public.inventory VALUES (45, 60, 1, 'test', 'test', 100, 1, 'demo');
INSERT INTO public.inventory VALUES (36, 78, 1, '4', NULL, 221, 6, 'W1 55');
INSERT INTO public.inventory VALUES (41, 69, 1, '3', NULL, 103, 3, 'W1 52');


--
-- TOC entry 3831 (class 0 OID 34326)
-- Dependencies: 227
-- Data for Name: inventory_halstan_staging; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.inventory_halstan_staging VALUES ('Fair Haven', 'W1 07', 910, 14, '1', NULL, 7, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Night Watch C. Boston - VS', 'W1 08', 521, 11, '1', NULL, 8, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Night Watch C. Boston - FS', 'W1 09', 100, 3, '2', NULL, 9, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('The Blue Goat', 'W1 11', 65, 2, '2', NULL, 11, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Octet for Wind Instruments', 'W1 19', 35, 1, '3', NULL, 18, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Dien Vous Gard - score & part', 'W1 21', 50, 1, '3', NULL, 20, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Ballons & Frog Music', 'W1 22', 43, 1, '3', NULL, 21, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Die Landung', 'W1 29', 230, 1, '3', NULL, 28, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Unrhe ', 'W1 30', 230, 2, '1', NULL, 29, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Asyl', 'W1 31', 230, 1, '3', NULL, 30, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('3 Pieces for Organ - Vol 2', 'W1 33', 355, 4, 'RACK B7', NULL, 32, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('3 Pieces for Organ - Vol 3', 'W1 34', 354, 4, 'RACK B7', NULL, 33, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Psalm 121, 33', 'W1 37', 0, NULL, NULL, NULL, 36, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Wind Quintet - Score', 'W1 43', 48, 2, '3', NULL, 41, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Satisfied ', 'W1 44', 84, 1, '3', NULL, 42, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Feed My Sheep', 'W1 45', 58, 1, '3', NULL, 43, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Christ My Refuge', 'W1 46', 83, 1, '3', NULL, 44, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Wind QuINTETparts', 'W1 48', 130, 2, '3', NULL, 46, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Opera 17 - score', 'W1 51', 25, 1, '3', NULL, 48, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('To a Waterfowl - score & parts', 'W1 53', 34, NULL, '0', NULL, 50, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Christmas Morn', 'W1 57', 200, 1, '4', NULL, 53, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Mothers Evening Prayer', 'W1 59', 95, 1, '4', NULL, 54, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Genesis 45 - A Symphonic Poem', 'W1 63', 52, 1, '4', NULL, 56, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Witches Broom Notes', 'W1 67', 120, 3, '4', NULL, 59, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Canata No.82', 'W1 68', 70, 1, '4', NULL, 60, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Lutenists Solo & Duet Book', 'W1 71', 100, 3, '4', NULL, 63, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Isaiah 60 1,2,3', 'W1 76', 200, 1, '4', NULL, 68, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('5 Childrens Songs for Adults', 'W1 78', 189, 2, '4', NULL, 70, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Trio for Woodwind', 'W1 79', 28, 1, '4', NULL, 71, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('THEE LOVE SONGS', 'W1 80', 220, 2, '4', NULL, 72, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('DUBIESK VIOLA', 'W1 81', 250, 5, '4', NULL, 73, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('TRIO PIANO TRPT CLAR', 'W1 82', 269, 12, '4', NULL, 74, NULL);
INSERT INTO public.inventory_halstan_staging VALUES ('Sextet for Wind', 'W1 77', 180, 12, '4', NULL, 69, 18);
INSERT INTO public.inventory_halstan_staging VALUES ('Concerto for Trumpet & Viola', 'W1 20', 35, 1, '3', NULL, 19, 76);
INSERT INTO public.inventory_halstan_staging VALUES ('Viola Concerto Score & Parts', 'W1 75', 50, 4, '4', NULL, 67, 2);
INSERT INTO public.inventory_halstan_staging VALUES ('Consort for Baroque Flute & Horn', 'W1 06', 68, 1, '1', NULL, 6, 3);
INSERT INTO public.inventory_halstan_staging VALUES ('Five Songs in Five Minutes', 'W1 10', 17, 1, '2', NULL, 10, 5);
INSERT INTO public.inventory_halstan_staging VALUES ('Five Duets for Woodwinds', 'W1 13', 71, 1, '2', NULL, 13, 6);
INSERT INTO public.inventory_halstan_staging VALUES ('For Two Saxophones', 'W1 05', 87, 1, '1', NULL, 5, 10);
INSERT INTO public.inventory_halstan_staging VALUES ('Quintet for Brass - score & parts', 'W1 69', 169, 4, '4', NULL, 61, 12);
INSERT INTO public.inventory_halstan_staging VALUES ('Saxophone Quartet', 'W1 04', 0, 0, NULL, NULL, 4, 15);
INSERT INTO public.inventory_halstan_staging VALUES ('Jonah - score & parts', 'W1 15', 110, 3, '2', NULL, 15, 18);
INSERT INTO public.inventory_halstan_staging VALUES ('Suite for Harp & Flute', 'W1 40', 0, NULL, NULL, NULL, 39, 19);
INSERT INTO public.inventory_halstan_staging VALUES ('Suite for Recorders', 'W1 38', 0, NULL, NULL, NULL, 37, 20);
INSERT INTO public.inventory_halstan_staging VALUES ('Suite for Two Bassoons', 'W1 36', 130, 1, '3', NULL, 35, 21);
INSERT INTO public.inventory_halstan_staging VALUES ('Theme & Variations for 4 Brass Instr.', 'W1 17', 30, 1, '3', NULL, 17, 22);
INSERT INTO public.inventory_halstan_staging VALUES ('Trio for Clarinet/Horn/Bassoon', 'W1 35', 150, 1, '3', NULL, 34, 23);
INSERT INTO public.inventory_halstan_staging VALUES ('Trio for Flute /Oboe /Piano', 'W1 01', 78, 1, '1', NULL, 1, 24);
INSERT INTO public.inventory_halstan_staging VALUES ('Trio for 3 Saxophones - parts', 'W1 64', 90, 2, '4', NULL, 57, 26);
INSERT INTO public.inventory_halstan_staging VALUES ('Trio for 3 Saxophones - score', 'W1 70', 35, 1, '4', NULL, 62, 27);
INSERT INTO public.inventory_halstan_staging VALUES ('Sonata for Violin & Piano', 'W1 16', 97, 1, '3', NULL, 16, 31);
INSERT INTO public.inventory_halstan_staging VALUES ('Keyboard Suite', 'W1 27', 322, 2, '3', NULL, 26, 36);
INSERT INTO public.inventory_halstan_staging VALUES ('Processional for Radcliffe', 'W1 72', 170, 1, '4', NULL, 64, 39);
INSERT INTO public.inventory_halstan_staging VALUES ('Ride a Cock Horse', 'W1 39', 0, NULL, NULL, NULL, 38, 40);
INSERT INTO public.inventory_halstan_staging VALUES ('3 Pieces for Organ - Vol 1 ', 'W1 32', 247, 2, 'RACK B7', NULL, 31, 41);
INSERT INTO public.inventory_halstan_staging VALUES ('Three Sonatas for Piano', 'W1 42', 175, 3, '3', NULL, 40, 44);
INSERT INTO public.inventory_halstan_staging VALUES ('Quartet for Strings', 'W1 03', 100, 1, '1', NULL, 3, 52);
INSERT INTO public.inventory_halstan_staging VALUES ('Quartet for Strings - No.2', 'W1 66', 25, 1, '4', NULL, 58, 53);
INSERT INTO public.inventory_halstan_staging VALUES ('Quartet for Strings No.3 - parts', 'W1 49', 59, 1, '3', NULL, 47, 54);
INSERT INTO public.inventory_halstan_staging VALUES ('Quartet for Strings No.3 - score', 'W1 47', 60, 1, '3', NULL, 45, 55);
INSERT INTO public.inventory_halstan_staging VALUES ('String QuINet - score & parts', 'W1 73', 163, 4, '4', NULL, 65, 58);
INSERT INTO public.inventory_halstan_staging VALUES ('Suite for Cello & Flute', 'W1 02', 70, 1, '1', NULL, 2, 59);
INSERT INTO public.inventory_halstan_staging VALUES ('Suite for Violin & Cello', 'W1 14', 99, 1, '2', NULL, 14, 60);
INSERT INTO public.inventory_halstan_staging VALUES ('24 Duets for Violin & Cello', 'W1 62', 93, 1, '4', NULL, 55, 63);
INSERT INTO public.inventory_halstan_staging VALUES ('Gift of the Magi - VS', 'W1 28', 235, 3, '3', NULL, 27, 64);
INSERT INTO public.inventory_halstan_staging VALUES ('To a Waterfowl - vocal score ', 'W1 54', 185, 1, '3', NULL, 51, 65);
INSERT INTO public.inventory_halstan_staging VALUES ('Seventeen - vocal score', 'W1 52', 105, 3, '3', NULL, 49, 69);
INSERT INTO public.inventory_halstan_staging VALUES ('Ballons & Frog Music - Instr. score', 'W1 23', 18, 1, '3', NULL, 22, 74);
INSERT INTO public.inventory_halstan_staging VALUES ('Concerto for Trumpet & Viola', 'W1 83', 270, 7, '4', NULL, 75, 76);
INSERT INTO public.inventory_halstan_staging VALUES ('Little Concerto - piano & violin', 'W1 55', 222, 6, '4', NULL, 52, 78);
INSERT INTO public.inventory_halstan_staging VALUES ('Symphony No.1', 'W1 24', 25, 1, '3', NULL, 23, 85);
INSERT INTO public.inventory_halstan_staging VALUES ('Symphony No.2', 'W1 25', 20, 1, '3', NULL, 24, 86);
INSERT INTO public.inventory_halstan_staging VALUES ('Symphony No.3', 'W1 26', 20, 1, '3', NULL, 25, 87);
INSERT INTO public.inventory_halstan_staging VALUES ('Viola Concerto - score', 'W1 74', 110, 2, '4', NULL, 66, 89);
INSERT INTO public.inventory_halstan_staging VALUES ('263 Settings of 73 Chorale M', 'W1 12', 515, 55, '2', 'RACK B7', 12, 91);


--
-- TOC entry 3838 (class 0 OID 41771)
-- Dependencies: 238
-- Data for Name: inventory_movement; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.inventory_movement VALUES (1, 59, 1, NULL, 1, 'sale', '2025-12-04 00:02:15.318541', 'order 6');
INSERT INTO public.inventory_movement VALUES (2, 54, 1, NULL, 1, 'sale', '2025-12-04 00:12:13.101591', 'order 7');
INSERT INTO public.inventory_movement VALUES (3, 44, 1, NULL, 1, 'sale', '2025-12-04 02:15:55.590753', 'order 12');
INSERT INTO public.inventory_movement VALUES (4, 76, 1, NULL, 1, 'sale', '2025-12-04 03:39:46.796054', 'order 13');
INSERT INTO public.inventory_movement VALUES (5, 44, 1, NULL, 1, 'sale', '2025-12-04 03:54:24.142346', 'order 13');
INSERT INTO public.inventory_movement VALUES (6, 44, 1, NULL, 1, 'sale', '2025-12-04 05:33:42.893743', 'order 14');
INSERT INTO public.inventory_movement VALUES (7, 76, 1, NULL, 1, 'sale', '2025-12-04 05:34:06.208895', 'order 15');
INSERT INTO public.inventory_movement VALUES (8, 44, 1, NULL, 1, 'sale', '2025-12-04 05:34:16.763183', 'order 15');
INSERT INTO public.inventory_movement VALUES (9, 54, 1, NULL, 2, 'sale', '2025-12-04 05:34:33.096232', 'order 15');
INSERT INTO public.inventory_movement VALUES (10, 65, 1, NULL, 1, 'sale', '2025-12-04 22:27:27.435501', 'order 16');
INSERT INTO public.inventory_movement VALUES (11, 91, 1, NULL, 1, 'sale', '2025-12-04 22:30:01.413616', 'order 16');
INSERT INTO public.inventory_movement VALUES (12, 31, 1, NULL, 1, 'sale', '2025-12-05 09:52:44.076969', 'order 18');
INSERT INTO public.inventory_movement VALUES (13, 52, 1, NULL, 1, 'sale', '2025-12-05 09:53:32.183784', 'order 20');
INSERT INTO public.inventory_movement VALUES (14, 52, 1, NULL, 1, 'sale', '2025-12-05 09:53:40.975014', 'order 20');
INSERT INTO public.inventory_movement VALUES (15, 48, 1, NULL, 1, 'sale', '2025-12-05 09:54:06.71895', 'order 20');
INSERT INTO public.inventory_movement VALUES (16, 78, 1, NULL, 1, 'sale', '2025-12-05 16:39:41.56525', 'order 21');
INSERT INTO public.inventory_movement VALUES (17, 69, 1, NULL, 1, 'sale', '2025-12-05 16:40:17.553918', 'order 22');
INSERT INTO public.inventory_movement VALUES (18, 69, 1, NULL, 1, 'sale', '2025-12-05 16:40:19.811243', 'order 22');


--
-- TOC entry 3830 (class 0 OID 34272)
-- Dependencies: 226
-- Data for Name: location; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.location VALUES (1, 'Halstan UK');
INSERT INTO public.location VALUES (2, 'London UK');
INSERT INTO public.location VALUES (3, 'Mason US');
INSERT INTO public.location VALUES (4, 'Basement US');


--
-- TOC entry 3834 (class 0 OID 41684)
-- Dependencies: 230
-- Data for Name: music_product; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.music_product VALUES (91, '263 Settings of 73 Chorale Melodies', NULL, NULL, NULL, NULL, NULL, NULL, false, NULL, false, false, 'W1 12', 'J.S. Bach', 'Editor: Mary Phillips Webster', 'Editor: B. F. Warren-Davis', 'print', NULL, NULL, 1982, NULL, 'Book');
INSERT INTO public.music_product VALUES (10, 'For Two Saxophones', '[4:00]', 1, 240, '4:00', '$4.50 ', 'M-58005-203-2', false, 10, false, false, 'W1 05', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (36, 'Keyboard Suite (six dances)', '[4:30]', 1, 270, '4:30', '$4.50 ', 'M-58005-001-4', false, 37, false, false, 'W1 27', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (21, 'Suite for two bassoons', '[5:30]', 1, 330, '5:30', '$8.00 ', 'M-58005-212-4', false, 21, false, false, 'W1 36', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (44, 'Three sonatas for piano', '[8:00; 7:30; 7:00]', 3, 1350, '22:30', '$9.50 ', 'M-58005-007-6', false, 45, false, false, 'W1 42', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (39, 'Processional for Radcliffe -- for organ', '[7:00]', 1, 420, '7:00', '$11.50 ', 'M-58005-002-1', false, 40, false, false, 'W1 72', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (18, 'Sextet for Winds 1011-1110 (score & parts)', '[11:15]', 1, 675, '11:15', '$28.50 ', 'M-58005-210-0', false, 18, false, false, 'W1 15', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (27, 'Trio for three saxophones (score)', '[14:00]', 1, 840, '14:00', '$19.50 ', 'M-58005-216-2', false, 27, false, false, 'W1 70', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (31, 'Encore for Violin and Piano', '[0:55]', 1, 55, '0:55', '$3.00 ', 'M-58005-127-1', true, 51, false, false, 'W1 16', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (40, '*Ride-a-cock horse (for piano)', '[4:30]', 1, 270, '4:30', '$3.50 ', 'M-58005-003-8', false, 41, true, false, 'W1 39', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (41, 'Three pieces for organ V. 1: Prelude, chorale prelude, fugue', '[6:00]', 1, 360, '6:00', '$13.00 ', 'M-58005-004-5', false, 42, false, false, 'W1 32', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (52, 'Quartet for Strings No. 1 (parts only)', '[11:30]', 1, 690, '11:30', '$8.00 ', 'M-58005-104-2', false, 57, false, false, 'W1 03', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (53, 'Quartet for Strings No. 2 (parts only)', '[18:30]', 1, 1110, '18:30', '$10.50 ', 'M-58005-106-6', false, 58, false, false, 'W1 66', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (54, 'Quartet for Strings No. 3 (parts)', '[18:00]', 1, 1080, '18:00', '$9.00 ', 'M-58005-108-0', false, 59, false, false, 'W1 49', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (69, 'Seventeen (Booth Tarkington) 1111-B.CL-2000 S.D. strings piano-vocal score', '[90:00]', 1, 5400, '90:00', '$11.00 ', 'M-58005-711-2', false, 75, false, true, 'W1 52', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (74, 'Balloons & Frog Music (two ballets based on poems by David McCord) 1111-0000 –v, CB piano score', '[11:00]', 1, 660, '11:00', '$11.00 ', 'M-58005-700-6', false, 80, false, true, 'W1 23', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (76, '*Concerto for trumpet & viola 1001-0000 – strings full score', '[7:00]', 1, 420, '7:00', '$18.00 ', 'M-58005-702-0', false, 82, true, true, 'W1 83', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (78, 'Little Concerto for Violin 0011-0000 - percussion-strings piano score', '[13:00]', 1, 780, '13:00', '$13.00 ', 'M-58005-718-1', false, 86, false, true, 'W1 55', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (85, '*Symphony no. 1 1111-2200 - strings', '[22:00]', 1, 1320, '22:00', '$49.50 ', 'M-58005-722-8', false, 94, true, true, 'W1 24', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (86, '*Symphony no. 2 1111-1110 - strings', '[20:00]', 1, 1200, '20:00', '$49.50 ', 'M-58005-723-5', false, 95, true, true, 'W1 25', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (87, '*Symphony no. 3 1111-2110 - strings', '[20:00]', 1, 1200, '20:00', '$49.50 ', 'M-58005-724-2', false, 96, true, true, 'W1 26', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (89, 'Viola Concerto (oboe, tubular bells, strings) piano-viola score', '[10:00]', 1, 600, '10:00', '$11.00 ', 'M-58005-726-6', false, 98, false, true, 'W1 74', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (6, 'Five Duets for Woodwinds', '[5:00]', 1, 300, '5:00', '$7.00 ', 'M-58005-202-5', false, 6, false, false, 'W1 13', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (2, 'Concerto for trumpet and piano orchestrated for trumpet & strings: full score & parts', '[9:10]', 1, 550, '9:10', '$23.00 ', 'M-58005-705-1', true, 84, false, true, 'W1 75', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (3, 'Consort for Baroque flute & harpsichord', '[5:00]', 1, 300, '5:00', '$8.00 ', 'M-58005-201-8', false, 3, false, false, 'W1 06', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (5, 'The Encore Trumpet: trumpet solo in three minutes', '[2:54]', 1, 174, '2:54', '$5.50 ', 'M-58005-223-0', false, 5, false, false, 'W1 10', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (1, 'Concerto for trumpet and piano Trumpet and piano score', '[9:10]', 1, 550, '9:10', '$10.00 ', 'M-58005-704-4', true, 83, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (4, 'Duet for Alto Flute and Cello', '[2:30]', 1, 150, '2:30', '$5.50 ', 'M-58005-224-7', true, 49, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (7, '*For Five Trumpets and Trumpet and Percussion', '[0:36]', 1, 36, '0:36', '$11.00 ', 'M-58005-221-6', false, 7, true, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (8, 'For George and Josephine (for trumpet and flute)', '[2:25]', 1, 145, '2:25', '$10.00 ', 'M-58005-222-3', false, 8, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (9, 'For Trumpet and Organ', '[5:50]', 1, 350, '5:50', '$6.50 ', 'M-58005-226-1', true, 9, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (11, 'It Bringeth forth Fruit (for oboe, clarinet and bassoon; also scored for violin, viola, and cello)', '[0:53; 0:48; 1:15]', 3, 176, '2:56', '$6.50 ', 'M-58005-227-8', false, 11, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (13, 'Quintet for Brass, No. 2 0000-1211 (score & parts)', '[4:16; 2:35; 2:11]', 3, 542, '9:02', '$17.00 ', 'M-58005-225-4', false, 13, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (14, 'Quintet for Winds, 1111-1000 (score & parts)', '[15:00]', 1, 900, '15:00', '$40.00 ', 'M-58005-206-3', false, 14, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (16, 'Saxophone Quartet No. 2 (score and parts)', '[1:35; 1:50; 2:45]', 3, 370, '6:10', '$11.00 ', 'M-58005-228-5', false, 16, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (17, 'Seven excerpts from Washington’s Farewell Address 0000-0440 & speaker', '[10:00]', 1, 600, '10:00', '$16.50 ', 'M-58005-209-4', true, 93, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (25, 'Trio for oboe, clarinet, and bass flute (or oboe and two violas)', '[8:00]', 1, 480, '8:00', '$18.50 ', 'M-58005-217-9', false, 25, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (28, 'Trio for trumpet, clarinet and piano (score and parts)', '[7:50]', 1, 470, '7:50', '$12.50 ', 'M-58005-220-9', false, 28, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (29, '*Trio for trumpet, violin and cello in three movements (in process)', '[1:10; 1:05; 0:53]', 3, 188, '3:08', NULL, 'M-58005-123-3', false, 29, true, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (30, 'Two for Twenty (for cello and clarinet in A)', '[2:00]', 1, 120, '2:00', '$6.00 ', 'M-58005-118-9', true, 69, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (32, 'For Violin and Piano', '[1:30; 0:55; 5:10]', 3, 455, '7:35', '$10.00 ', 'M-58005-126-4', true, 52, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (33, 'Four Snippets for Organ', '[0:42; 0:51; 0:38; 0:43]', 4, 174, '2:54', '$3.50 ', 'M-58005-008-3', false, 34, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (34, '*The Island (for piano)', '[5:15]', 1, 315, '5:15', '$6.50 ', 'M-58005-000-7', false, 35, true, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (35, 'It Bringeth forth Fruit (for piano; also scored for oboe, clarinet, and bassoon, and violin, viola and cello)', '[0:53; 0:48; 1:15]', 3, 176, '2:56', '$4.00 ', 'M-58005-009-0', false, 36, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (37, 'Piano Quartet, No. 1 (for piano, violin, viola, and cello)', '[7:00]', 1, 420, '7:00', '$18.50 ', 'M-58005-120-2', true, 55, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (38, 'Piano Quartet, No. 2 (for piano, violin, viola, and cello)', '[9:45]', 1, 585, '9:45', '$19.00 ', 'M-58005-121-9', false, 39, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (42, 'Three pieces for organ V. 2: Prelude, chorale prelude, passacaglia', '[9:00]', 1, 540, '9:00', '$16.00 ', 'M-58005-005-2', false, 43, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (43, 'Three pieces for organ V. 3: Theme & variations, chorale prelude, fantasia', '[12:00]', 1, 720, '12:00', '$15.00 ', 'M-58005-006-9', false, 44, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (45, 'Blue Goat (guitar solo)', '[5:15]', 1, 315, '5:15', '$5.50 ', 'M-58005-100-4', false, 46, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (46, 'Cantata no. 82 (clarinet, violin, viola, cello) score & parts', '[7:00]', 1, 420, '7:00', '$16.50 ', 'M-58005-101-1', false, 47, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (47, 'Dubiesk (sonata for viola and piano)', '[3:50]', 1, 230, '3:50', '$4.50 ', 'M-58005-102-8', false, 48, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (48, 'The Encore (for cello & piano)', '[6:45]', 1, 405, '6:45', '$13.00 ', 'M-58005-119-6', false, 50, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (49, 'It Bringeth forth Fruit for violin, viola and cello (also scored for piano, and for oboe, clarinet, and bassoon)', '[0:53; 0:48; 1:15]', 3, 176, '2:56', '$6.50 ', 'M-58005-128-8', false, 53, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (50, 'The Lutenist’s Solo & Duet Book', '[9:30]', 1, 570, '9:30', '$23.00 ', 'M-58005-103-5', false, 54, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (51, 'Quartet for Marabelle (for two violins, cello, and piano)', '[9:30]', 1, 570, '9:30', '$16.50 ', 'M-58005-122-6', false, 56, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (12, 'Quintet for Brass, No. 1 0000-1211 (score & parts)', '[20:00]', 1, 1200, '20:00', '$28.50 ', 'M-58005-204-9', false, 12, false, false, 'W1 69', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (15, 'Saxophone Quartet No. 1 (score and parts)', '[8:00]', 1, 480, '8:00', '$11.00 ', 'M-58005-208-7', false, 15, false, false, 'W1 04', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (19, 'Sonata for Harp & Flute', '[5:30]', 1, 330, '5:30', '$8.00 ', 'M-58005-211-7', false, 19, false, false, 'W1 40', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (20, 'Suite for three recorders (parts only)', '[4:00]', 1, 240, '4:00', '$8.00 ', 'M-58005-213-1', false, 20, false, false, 'W1 38', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (22, '*Theme and variations for four brass instruments 0000-1201 (score and parts)', '[3:00]', 1, 180, '3:00', '$7.00 ', 'M-58005-214-8', false, 22, true, false, 'W1 17', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (23, 'Trio for clarinet, horn, and bassoon (parts)', '[10:00]', 1, 600, '10:00', '$8.00 ', 'M-58005-218-6', false, 23, false, false, 'W1 35', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (24, 'Trio for flute, oboe and piano (score and parts)', '[8:30]', 1, 510, '8:30', '$10.50 ', 'M-58005-219-3', false, 24, false, false, 'W1 01', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (26, 'Trio for three saxophones (parts only)', '[14:00]', 1, 840, '14:00', '$16.50 ', 'M-58005-215-5', false, 26, false, false, 'W1 64', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (56, 'Sonata, violin & piano, No. 1', '[5:30]', 1, 330, '5:30', '$11.50 ', 'M-58005-111-0', false, 61, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (57, 'Sonata, violin & piano, No. 2', '[9:00]', 1, 540, '9:00', '$19.00 ', 'M-58005-112-7', false, 62, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (61, 'Trio for violin, viola, & cello, No. 1 (score and parts)', '[15:00]', 1, 900, '15:00', '$18.00 ', 'M-58005-116-5', false, 66, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (62, 'Trio for Violin, Viola, & Cello, No. 2 Dedicated to the Albers Trio', '[1:25; 0:45; 1:05; 0:52]', 4, 247, '4:07', '$8.00 ', 'M-58005-124-0', false, 67, false, false, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (66, '*Gift of the Magi (O. Henry – D.McCord) 0101-2000 strings full score', '[18:00]', 1, 1080, '18:00', '$25.50 ', 'M-58005-708-2', false, 72, true, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (67, '*The Rose & The Ring (W.M. Thackeray) 1111-1100 timp.-strings-chorus piano-vocal score', '[45:00]', 1, 2700, '45:00', '$11.00 ', 'M-58005-709-9', false, 73, true, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (68, '*The Rose & The Ring (W.M. Thackeray) 1111-1100 timp.-strings-chorus full score', '[45:00]', 1, 2700, '45:00', '$33.00 ', 'M-58005-710-5', false, 74, true, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (70, 'Seventeen (Booth Tarkington) 1111-B.CL-2000 S.D. strings full score', '[90:00]', 1, 5400, '90:00', '$22.00 ', 'M-58005-712-9', false, 76, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (71, 'Thomas Shelby (H.B. Stowe) 1111-timp.-strings-chorus or 1011-1110 C.B.-chorus piano-vocal score', '[75:00]', 1, 4500, '75:00', '$16.50 ', 'M-58005-713-6', false, 77, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (72, 'Thomas Shelby (H.B. Stowe) 1111-timp.-strings-chorus or 1011-1110 C.B.-chorus chamber score', '[75:00]', 1, 4500, '75:00', '$25.00 ', 'M-58005-714-3', false, 78, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (73, 'Thomas Shelby (H.B. Stowe) 1111-timp.-strings-chorus or 1011-1110 C.B.-chorus full orchestral score', '[75:00]', 1, 4500, '75:00', '$27.50 ', 'M-58005-715-0', false, 79, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (75, 'Balloons & Frog Music (two ballets based on poems by David McCord) 1111-0000 –v, CB full score', '[11:00]', 1, 660, '11:00', '$22.00 ', 'M-58005-701-3', false, 81, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (77, 'Kaleidoscope (for orchestra) 1111-2220 timp. + glockenspiel-strings', '[7:00]', 1, 420, '7:00', '$28.50 ', 'M-58005-717-4', false, 85, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (79, 'Little Concerto for Violin 0011-0000 - percussion-strings full score', '[13:00]', 1, 780, '13:00', '$21.00 ', 'M-58005-719-8', false, 87, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (80, 'Little Symphony 2202-2020-timp.-strings full score', '[5:20]', 1, 320, '5:20', '$40.00 ', 'M-58005-728-0', false, 88, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (81, 'Little Symphony 2202-2020-timp.-strings complete parts -- available for hire', '[5:20]', 1, 320, '5:20', NULL, 'M-58005-729-7', false, 89, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (82, 'Octet 0222-2000', '[10:00]', 1, 600, '10:00', '$16.50 ', 'M-58005-720-4', false, 90, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (83, 'The Second Movement 2202-2200 - timp. & strings full score', '[5:00]', 1, 300, '5:00', '$25.00 ', 'M-58005-721-1', false, 91, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (84, 'The Second Movement 2202-2200 - timp. & strings complete parts -- available for hire', '[5:00]', 1, 300, '5:00', NULL, 'M-___________', false, 92, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (88, 'Triple Concerto for piano, violin, cello & orchestra 1111-2020-strings', '[15:00]', 1, 900, '15:00', '$41.00 ', 'M-58005-725-9', false, 97, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (90, 'Viola Concerto (oboe, tubular bells, strings) full score', '[10:00]', 1, 600, '10:00', '$20.00 ', 'M-58005-727-3', false, 99, false, true, NULL, 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (55, 'Quartet for Strings No. 3 (score)', '[18:00]', 1, 1080, '18:00', '$13.00 ', 'M-58005-109-7', false, 60, false, false, 'W1 47', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (58, 'String Quintet (string quartet & double bass) score and parts', '[15:30]', 1, 930, '15:30', '$33.00 ', 'M-58005-113-4', false, 63, false, false, 'W1 73', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (59, 'Suite for cello & flute', '[5:00]', 1, 300, '5:00', '$5.50 ', 'M-58005-114-1', false, 64, false, false, 'W1 02', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (60, 'Suite for violin & cello', '[7:00]', 1, 420, '7:00', '$11.50 ', 'M-58005-115-8', false, 65, false, false, 'W1 14', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (63, 'Twenty-four duets for violin and cello', '[8:00]', 1, 480, '8:00', '$11.00 ', 'M-58005-117-2', false, 68, false, false, 'W1 62', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (64, '*Gift of the Magi (O. Henry – D.McCord) 0101-2000 strings libretto', '[18:00]', 1, 1080, '18:00', '$1.50 ', 'M-58005-706-8', false, 70, true, true, 'W1 28', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');
INSERT INTO public.music_product VALUES (65, '*Gift of the Magi (O. Henry – D.McCord) 0101-2000 strings piano-vocal score', '[18:00]', 1, 1080, '18:00', '$13.00 ', 'M-58005-707-5', false, 71, true, true, 'W1 54', 'B. Warren', NULL, NULL, 'print', NULL, NULL, NULL, NULL, 'Sheet Music');


--
-- TOC entry 3826 (class 0 OID 34191)
-- Dependencies: 222
-- Data for Name: order_line; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.order_line VALUES (6, 6, 59, 19.95, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (7, 7, 54, 21.37, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (8, 12, 44, 9.50, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (9, 13, 76, 18.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (10, 13, 44, 18.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (11, 14, 44, 9.50, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (12, 15, 76, 9.50, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (13, 15, 44, 9.50, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (14, 15, 54, 9.50, 2, 1, DEFAULT);
INSERT INTO public.order_line VALUES (15, 16, 65, 13.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (16, 16, 91, 50.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (17, 18, 31, 3.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (18, 20, 52, 8.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (19, 20, 52, 8.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (20, 20, 48, 13.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (21, 21, 78, 13.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (22, 22, 69, 11.00, 1, 1, DEFAULT);
INSERT INTO public.order_line VALUES (23, 22, 69, 11.00, 1, 1, DEFAULT);


--
-- TOC entry 3824 (class 0 OID 34164)
-- Dependencies: 220
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.orders VALUES (3, '2025-12-03', 1, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (4, '2025-12-03', 2, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (5, '2025-12-03', 1, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (6, '2025-12-04', 3, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (7, '2025-12-04', 3, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (8, '2025-12-04', 3, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (9, '2025-12-04', 3, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (10, '2025-12-04', 1, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (11, '2025-12-04', 1, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (12, '2025-12-04', 1, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (13, '2025-12-04', 2, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (14, '2025-12-04', 2, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (15, '2025-12-04', 2, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (16, '2025-12-04', 2, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (17, '2025-12-05', 5, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (18, '2025-12-05', 5, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (19, '2025-12-05', 5, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (20, '2025-12-05', 5, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (21, '2025-12-05', 3, NULL, NULL, NULL, NULL, NULL);
INSERT INTO public.orders VALUES (22, '2025-12-05', 3, NULL, NULL, NULL, NULL, NULL);


--
-- TOC entry 3835 (class 0 OID 41691)
-- Dependencies: 231
-- Data for Name: product_category_junction; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.product_category_junction VALUES (1, 1);
INSERT INTO public.product_category_junction VALUES (1, 5);
INSERT INTO public.product_category_junction VALUES (2, 1);
INSERT INTO public.product_category_junction VALUES (2, 5);
INSERT INTO public.product_category_junction VALUES (3, 1);
INSERT INTO public.product_category_junction VALUES (4, 1);
INSERT INTO public.product_category_junction VALUES (4, 3);
INSERT INTO public.product_category_junction VALUES (5, 1);
INSERT INTO public.product_category_junction VALUES (6, 1);
INSERT INTO public.product_category_junction VALUES (7, 1);
INSERT INTO public.product_category_junction VALUES (8, 1);
INSERT INTO public.product_category_junction VALUES (9, 1);
INSERT INTO public.product_category_junction VALUES (9, 2);
INSERT INTO public.product_category_junction VALUES (10, 1);
INSERT INTO public.product_category_junction VALUES (11, 1);
INSERT INTO public.product_category_junction VALUES (12, 1);
INSERT INTO public.product_category_junction VALUES (13, 1);
INSERT INTO public.product_category_junction VALUES (14, 1);
INSERT INTO public.product_category_junction VALUES (15, 1);
INSERT INTO public.product_category_junction VALUES (16, 1);
INSERT INTO public.product_category_junction VALUES (17, 1);
INSERT INTO public.product_category_junction VALUES (17, 5);
INSERT INTO public.product_category_junction VALUES (18, 1);
INSERT INTO public.product_category_junction VALUES (19, 1);
INSERT INTO public.product_category_junction VALUES (20, 1);
INSERT INTO public.product_category_junction VALUES (21, 1);
INSERT INTO public.product_category_junction VALUES (22, 1);
INSERT INTO public.product_category_junction VALUES (23, 1);
INSERT INTO public.product_category_junction VALUES (24, 1);
INSERT INTO public.product_category_junction VALUES (25, 1);
INSERT INTO public.product_category_junction VALUES (26, 1);
INSERT INTO public.product_category_junction VALUES (27, 1);
INSERT INTO public.product_category_junction VALUES (28, 1);
INSERT INTO public.product_category_junction VALUES (29, 1);
INSERT INTO public.product_category_junction VALUES (30, 1);
INSERT INTO public.product_category_junction VALUES (30, 3);
INSERT INTO public.product_category_junction VALUES (31, 2);
INSERT INTO public.product_category_junction VALUES (31, 3);
INSERT INTO public.product_category_junction VALUES (32, 2);
INSERT INTO public.product_category_junction VALUES (32, 3);
INSERT INTO public.product_category_junction VALUES (33, 2);
INSERT INTO public.product_category_junction VALUES (34, 2);
INSERT INTO public.product_category_junction VALUES (35, 2);
INSERT INTO public.product_category_junction VALUES (36, 2);
INSERT INTO public.product_category_junction VALUES (37, 2);
INSERT INTO public.product_category_junction VALUES (37, 3);
INSERT INTO public.product_category_junction VALUES (38, 2);
INSERT INTO public.product_category_junction VALUES (39, 2);
INSERT INTO public.product_category_junction VALUES (40, 2);
INSERT INTO public.product_category_junction VALUES (41, 2);
INSERT INTO public.product_category_junction VALUES (42, 2);
INSERT INTO public.product_category_junction VALUES (43, 2);
INSERT INTO public.product_category_junction VALUES (44, 2);
INSERT INTO public.product_category_junction VALUES (45, 3);
INSERT INTO public.product_category_junction VALUES (46, 3);
INSERT INTO public.product_category_junction VALUES (47, 3);
INSERT INTO public.product_category_junction VALUES (48, 3);
INSERT INTO public.product_category_junction VALUES (49, 3);
INSERT INTO public.product_category_junction VALUES (50, 3);
INSERT INTO public.product_category_junction VALUES (51, 3);
INSERT INTO public.product_category_junction VALUES (52, 3);
INSERT INTO public.product_category_junction VALUES (53, 3);
INSERT INTO public.product_category_junction VALUES (54, 3);
INSERT INTO public.product_category_junction VALUES (55, 3);
INSERT INTO public.product_category_junction VALUES (56, 3);
INSERT INTO public.product_category_junction VALUES (57, 3);
INSERT INTO public.product_category_junction VALUES (58, 3);
INSERT INTO public.product_category_junction VALUES (59, 3);
INSERT INTO public.product_category_junction VALUES (60, 3);
INSERT INTO public.product_category_junction VALUES (61, 3);
INSERT INTO public.product_category_junction VALUES (62, 3);
INSERT INTO public.product_category_junction VALUES (63, 3);
INSERT INTO public.product_category_junction VALUES (64, 4);
INSERT INTO public.product_category_junction VALUES (65, 4);
INSERT INTO public.product_category_junction VALUES (66, 4);
INSERT INTO public.product_category_junction VALUES (67, 4);
INSERT INTO public.product_category_junction VALUES (68, 4);
INSERT INTO public.product_category_junction VALUES (69, 4);
INSERT INTO public.product_category_junction VALUES (70, 4);
INSERT INTO public.product_category_junction VALUES (71, 4);
INSERT INTO public.product_category_junction VALUES (72, 4);
INSERT INTO public.product_category_junction VALUES (73, 4);
INSERT INTO public.product_category_junction VALUES (74, 5);
INSERT INTO public.product_category_junction VALUES (75, 5);
INSERT INTO public.product_category_junction VALUES (76, 5);
INSERT INTO public.product_category_junction VALUES (77, 5);
INSERT INTO public.product_category_junction VALUES (78, 5);
INSERT INTO public.product_category_junction VALUES (79, 5);
INSERT INTO public.product_category_junction VALUES (80, 5);
INSERT INTO public.product_category_junction VALUES (81, 5);
INSERT INTO public.product_category_junction VALUES (82, 5);
INSERT INTO public.product_category_junction VALUES (83, 5);
INSERT INTO public.product_category_junction VALUES (84, 5);
INSERT INTO public.product_category_junction VALUES (85, 5);
INSERT INTO public.product_category_junction VALUES (86, 5);
INSERT INTO public.product_category_junction VALUES (87, 5);
INSERT INTO public.product_category_junction VALUES (88, 5);
INSERT INTO public.product_category_junction VALUES (89, 5);
INSERT INTO public.product_category_junction VALUES (90, 5);
INSERT INTO public.product_category_junction VALUES (91, 6);


--
-- TOC entry 3852 (class 0 OID 0)
-- Dependencies: 228
-- Name: category_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.category_category_id_seq', 6, true);


--
-- TOC entry 3853 (class 0 OID 0)
-- Dependencies: 217
-- Name: customer_customer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customer_customer_id_seq', 5, true);


--
-- TOC entry 3854 (class 0 OID 0)
-- Dependencies: 233
-- Name: inventory_halstan_staging_staging_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventory_halstan_staging_staging_id_seq', 75, true);


--
-- TOC entry 3855 (class 0 OID 0)
-- Dependencies: 223
-- Name: inventory_inventory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventory_inventory_id_seq', 85, true);


--
-- TOC entry 3856 (class 0 OID 0)
-- Dependencies: 237
-- Name: inventory_movement_movement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventory_movement_movement_id_seq', 18, true);


--
-- TOC entry 3857 (class 0 OID 0)
-- Dependencies: 225
-- Name: location_location_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.location_location_id_seq', 4, true);


--
-- TOC entry 3858 (class 0 OID 0)
-- Dependencies: 221
-- Name: order_line_order_line_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.order_line_order_line_id_seq', 23, true);


--
-- TOC entry 3859 (class 0 OID 0)
-- Dependencies: 219
-- Name: orders_order_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.orders_order_id_seq', 22, true);


--
-- TOC entry 3647 (class 2606 OID 41683)
-- Name: category category_category_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.category
    ADD CONSTRAINT category_category_name_key UNIQUE (category_name);


--
-- TOC entry 3649 (class 2606 OID 41681)
-- Name: category category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.category
    ADD CONSTRAINT category_pkey PRIMARY KEY (category_id);


--
-- TOC entry 3630 (class 2606 OID 34139)
-- Name: customer customer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (customer_id);


--
-- TOC entry 3645 (class 2606 OID 41720)
-- Name: inventory_halstan_staging inventory_halstan_staging_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_halstan_staging
    ADD CONSTRAINT inventory_halstan_staging_pkey PRIMARY KEY (staging_id);


--
-- TOC entry 3659 (class 2606 OID 41779)
-- Name: inventory_movement inventory_movement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movement
    ADD CONSTRAINT inventory_movement_pkey PRIMARY KEY (movement_id);


--
-- TOC entry 3636 (class 2606 OID 34258)
-- Name: inventory inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (inventory_id);


--
-- TOC entry 3640 (class 2606 OID 34279)
-- Name: location location_location_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_location_name_key UNIQUE (location_name);


--
-- TOC entry 3642 (class 2606 OID 34277)
-- Name: location location_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_pkey PRIMARY KEY (location_id);


--
-- TOC entry 3653 (class 2606 OID 41690)
-- Name: music_product music_product_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.music_product
    ADD CONSTRAINT music_product_pkey PRIMARY KEY (product_id);


--
-- TOC entry 3634 (class 2606 OID 34197)
-- Name: order_line order_line_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_line
    ADD CONSTRAINT order_line_pkey PRIMARY KEY (order_line_id);


--
-- TOC entry 3632 (class 2606 OID 34171)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (order_id);


--
-- TOC entry 3657 (class 2606 OID 41695)
-- Name: product_category_junction product_category_junction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_category_junction
    ADD CONSTRAINT product_category_junction_pkey PRIMARY KEY (product_id, category_id);


--
-- TOC entry 3638 (class 2606 OID 34260)
-- Name: inventory uq_inventory_product_location; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT uq_inventory_product_location UNIQUE (product_id, location_id);


--
-- TOC entry 3643 (class 1259 OID 41727)
-- Name: idx_halstan_staging_code_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_halstan_staging_code_title ON public.inventory_halstan_staging USING btree (halstan_code, title_raw);


--
-- TOC entry 3650 (class 1259 OID 41711)
-- Name: idx_music_product_ismn; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_music_product_ismn ON public.music_product USING btree (ismn);


--
-- TOC entry 3651 (class 1259 OID 41712)
-- Name: idx_music_product_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_music_product_title ON public.music_product USING btree (title);


--
-- TOC entry 3654 (class 1259 OID 41714)
-- Name: idx_product_category_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_category_category_id ON public.product_category_junction USING btree (category_id);


--
-- TOC entry 3655 (class 1259 OID 41713)
-- Name: idx_product_category_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_category_product_id ON public.product_category_junction USING btree (product_id);


--
-- TOC entry 3671 (class 2620 OID 41769)
-- Name: order_line order_line_inventory_aiud; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER order_line_inventory_aiud AFTER INSERT OR DELETE OR UPDATE ON public.order_line FOR EACH ROW EXECUTE FUNCTION public.order_line_inventory_movement();


--
-- TOC entry 3664 (class 2606 OID 41733)
-- Name: inventory inventory_location_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_location_fk FOREIGN KEY (location_id) REFERENCES public.location(location_id);


--
-- TOC entry 3668 (class 2606 OID 41785)
-- Name: inventory_movement inventory_movement_from_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movement
    ADD CONSTRAINT inventory_movement_from_location_id_fkey FOREIGN KEY (from_location_id) REFERENCES public.location(location_id);


--
-- TOC entry 3669 (class 2606 OID 41780)
-- Name: inventory_movement inventory_movement_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movement
    ADD CONSTRAINT inventory_movement_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.music_product(product_id);


--
-- TOC entry 3670 (class 2606 OID 41790)
-- Name: inventory_movement inventory_movement_to_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movement
    ADD CONSTRAINT inventory_movement_to_location_id_fkey FOREIGN KEY (to_location_id) REFERENCES public.location(location_id);


--
-- TOC entry 3665 (class 2606 OID 41728)
-- Name: inventory inventory_product_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_product_fk FOREIGN KEY (product_id) REFERENCES public.music_product(product_id);


--
-- TOC entry 3661 (class 2606 OID 41743)
-- Name: order_line order_line_fulfilled_from_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_line
    ADD CONSTRAINT order_line_fulfilled_from_location_id_fkey FOREIGN KEY (fulfilled_from_location_id) REFERENCES public.location(location_id);


--
-- TOC entry 3662 (class 2606 OID 34203)
-- Name: order_line order_line_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_line
    ADD CONSTRAINT order_line_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- TOC entry 3663 (class 2606 OID 41738)
-- Name: order_line order_line_product_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_line
    ADD CONSTRAINT order_line_product_fk FOREIGN KEY (product_id) REFERENCES public.music_product(product_id);


--
-- TOC entry 3660 (class 2606 OID 34172)
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customer(customer_id) ON DELETE SET NULL;


--
-- TOC entry 3666 (class 2606 OID 41701)
-- Name: product_category_junction product_category_junction_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_category_junction
    ADD CONSTRAINT product_category_junction_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.category(category_id);


--
-- TOC entry 3667 (class 2606 OID 41696)
-- Name: product_category_junction product_category_junction_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_category_junction
    ADD CONSTRAINT product_category_junction_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.music_product(product_id);


-- Completed on 2025-12-11 23:35:59 EST

--
-- PostgreSQL database dump complete
--

\unrestrict GRH4bAHtjEqpEKoIL6LLy0Y6MsfU8psxYi9WCc8MgjaPjTvbFJ0VnygIWimRlA7

