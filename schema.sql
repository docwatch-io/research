--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6 (Ubuntu 17.6-2.pgdg24.04+1)
-- Dumped by pg_dump version 17.6 (Ubuntu 17.6-2.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: warehouse; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS warehouse;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: community; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.community (
    id bigint NOT NULL,
    npi character varying(10) NOT NULL,
    canonical_community_id character varying(10) NOT NULL,
    effective_date date DEFAULT CURRENT_DATE NOT NULL,
    end_date date,
    is_current boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    community_type character varying(20),
    CONSTRAINT chk_community_type CHECK ((((community_type)::text = ANY ((ARRAY['institutional'::character varying, 'practice'::character varying])::text[])) OR (community_type IS NULL))),
    CONSTRAINT chk_effective_end_date CHECK (((end_date IS NULL) OR (end_date >= effective_date)))
);


--
-- Name: TABLE community; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON TABLE warehouse.community IS 'Historical community assignment data with SCD Type 2 implementation. Tracks when providers
join, leave, or move between communities over time. Each community is anchored to a CCN facility
from warehouse.place_of_service. Source data comes from Leiden clustering on NPI→CCN→parent relationships.';


--
-- Name: COLUMN community.npi; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.community.npi IS 'National Provider Identifier (10 digits)';


--
-- Name: COLUMN community.canonical_community_id; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.community.canonical_community_id IS 'CCN (CMS Certification Number) of the root facility in this community - links to warehouse.place_of_service.ccn';


--
-- Name: COLUMN community.effective_date; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.community.effective_date IS 'When this community assignment became effective';


--
-- Name: COLUMN community.end_date; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.community.end_date IS 'When this assignment was superseded (NULL for current)';


--
-- Name: COLUMN community.is_current; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.community.is_current IS 'True for the most recent community assignment of each provider';


--
-- Name: COLUMN community.community_type; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.community.community_type IS 'Type of community: institutional (CCN-based, hospital systems) or practice (NPI-NPI based, private practices)';


--
-- Name: community_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.community_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: community_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.community_id_seq OWNED BY warehouse.community.id;


--
-- Name: provider; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.provider (
    id bigint NOT NULL,
    npi character varying(10) NOT NULL,
    enumeration_type character varying(10),
    created_epoch character varying(20),
    last_updated_epoch character varying(20),
    basic jsonb,
    taxonomies jsonb,
    addresses jsonb,
    practice_locations jsonb,
    identifiers jsonb,
    endpoints jsonb,
    other_names jsonb,
    normalized_addresses text[],
    normalized_phone_numbers text[],
    source_file character varying(200),
    record_hash character varying(64) NOT NULL,
    effective_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    end_date timestamp with time zone,
    is_current boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_effective_end_date CHECK (((end_date IS NULL) OR (end_date > effective_date))),
    CONSTRAINT chk_enumeration_type CHECK ((((enumeration_type)::text = ANY ((ARRAY['NPI-1'::character varying, 'NPI-2'::character varying])::text[])) OR (enumeration_type IS NULL)))
)
WITH (autovacuum_enabled='true');


--
-- Name: TABLE provider; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON TABLE warehouse.provider IS 'Historical provider data with SCD Type 2 implementation. Stores complete change history
for all providers from NPPES data. Core table for API operations and historical analysis.';


--
-- Name: COLUMN provider.npi; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.npi IS 'National Provider Identifier (10 digits)';


--
-- Name: COLUMN provider.enumeration_type; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.enumeration_type IS 'Provider type: NPI-1 (Individual) or NPI-2 (Organization)';


--
-- Name: COLUMN provider.basic; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.basic IS 'Core provider information (name, status, etc.) in JSON format';


--
-- Name: COLUMN provider.taxonomies; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.taxonomies IS 'Provider taxonomies/specialties array in JSON format';


--
-- Name: COLUMN provider.addresses; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.addresses IS 'Provider addresses array in JSON format';


--
-- Name: COLUMN provider.source_file; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.source_file IS 'Source NPPES file that provided this data';


--
-- Name: COLUMN provider.record_hash; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.record_hash IS 'Hash of provider data for change detection during ETL';


--
-- Name: COLUMN provider.effective_date; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.effective_date IS 'When this version of the provider record became effective';


--
-- Name: COLUMN provider.end_date; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.end_date IS 'When this version was superseded (NULL for current records)';


--
-- Name: COLUMN provider.is_current; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.provider.is_current IS 'True for the most recent version of each provider';


--
-- Name: place_of_service; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.place_of_service (
    id bigint NOT NULL,
    ccn character varying(10) NOT NULL,
    facility_name text,
    provider_category_code character varying(2),
    provider_subtype_code character varying(2),
    street_address text,
    city text,
    state character varying(2),
    zip_code character varying(10),
    normalized_address text,
    normalized_phone character varying(30),
    certification_date date,
    termination_date date,
    parent_ccn character varying(10),
    matched_npi character varying(10),
    match_confidence numeric(3,2),
    match_method character varying(50),
    effective_date date NOT NULL,
    end_date date,
    is_current boolean DEFAULT true NOT NULL,
    source_file character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT place_of_service_check CHECK ((effective_date <= COALESCE(end_date, '9999-12-31'::date))),
    CONSTRAINT place_of_service_match_confidence_check CHECK (((match_confidence IS NULL) OR ((match_confidence >= (0)::numeric) AND (match_confidence <= (1)::numeric))))
);


--
-- Name: TABLE place_of_service; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON TABLE warehouse.place_of_service IS 'CMS Provider of Services (POS) file data with SCD Type 2 historical tracking.
Contains Medicare-certified facilities identified by CCN (CMS Certification Number).
Updated quarterly from https://data.cms.gov/provider-characteristics/hospitals-and-other-facilities/provider-of-services-file-hospital-non-hospital-facilities';


--
-- Name: COLUMN place_of_service.ccn; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.place_of_service.ccn IS 'CMS Certification Number (CCN) - 6-character Medicare facility identifier.
Format: XXYYYY where XX=state code, YYYY=facility sequence number.';


--
-- Name: COLUMN place_of_service.parent_ccn; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.place_of_service.parent_ccn IS 'CCN of parent organization (for hospital systems, multi-site facilities).
Creates CCN→CCN hierarchy similar to NPPES parent_org_ein.';


--
-- Name: COLUMN place_of_service.matched_npi; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.place_of_service.matched_npi IS 'NPI-2 (organization) matched via fuzzy name/address matching to NPPES data.
NULL if no match found. Populated by post-load matching process.';


--
-- Name: COLUMN place_of_service.match_confidence; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON COLUMN warehouse.place_of_service.match_confidence IS 'Confidence score (0.00-1.00) for matched_npi.
1.00 = exact name+address match, <0.80 = review recommended.';


--
-- Name: place_of_service_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.place_of_service_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: place_of_service_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.place_of_service_id_seq OWNED BY warehouse.place_of_service.id;


--
-- Name: provider_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.provider_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: provider_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.provider_id_seq OWNED BY warehouse.provider.id;


--
-- Name: community id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.community ALTER COLUMN id SET DEFAULT nextval('warehouse.community_id_seq'::regclass);


--
-- Name: place_of_service id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.place_of_service ALTER COLUMN id SET DEFAULT nextval('warehouse.place_of_service_id_seq'::regclass);


--
-- Name: provider id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.provider ALTER COLUMN id SET DEFAULT nextval('warehouse.provider_id_seq'::regclass);


--
-- Name: community community_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.community
    ADD CONSTRAINT community_pkey PRIMARY KEY (id);


--
-- Name: place_of_service place_of_service_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.place_of_service
    ADD CONSTRAINT place_of_service_pkey PRIMARY KEY (id);


--
-- Name: place_of_service place_of_service_unique_current; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.place_of_service
    ADD CONSTRAINT place_of_service_unique_current UNIQUE (ccn, effective_date) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: provider provider_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.provider
    ADD CONSTRAINT provider_pkey PRIMARY KEY (id);


--
-- Name: idx_community_type; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_community_type ON warehouse.community USING btree (community_type, is_current) WHERE (is_current = true);


--
-- Name: idx_place_of_service_ccn_current; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_place_of_service_ccn_current ON warehouse.place_of_service USING btree (ccn) WHERE (is_current = true);


--
-- Name: idx_place_of_service_effective_date; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_place_of_service_effective_date ON warehouse.place_of_service USING btree (effective_date);


--
-- Name: idx_place_of_service_end_date; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_place_of_service_end_date ON warehouse.place_of_service USING btree (end_date) WHERE (end_date IS NOT NULL);


--
-- Name: idx_place_of_service_facility_name_gin; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_place_of_service_facility_name_gin ON warehouse.place_of_service USING gin (to_tsvector('english'::regconfig, facility_name)) WHERE (is_current = true);


--
-- Name: idx_place_of_service_matched_npi; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_place_of_service_matched_npi ON warehouse.place_of_service USING btree (matched_npi) WHERE ((matched_npi IS NOT NULL) AND (is_current = true));


--
-- Name: idx_place_of_service_normalized_address; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_place_of_service_normalized_address ON warehouse.place_of_service USING btree (normalized_address) WHERE ((normalized_address IS NOT NULL) AND (is_current = true));


--
-- Name: INDEX idx_place_of_service_normalized_address; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON INDEX warehouse.idx_place_of_service_normalized_address IS 'B-tree index for CCN normalized_address lookups.
Used in joins with warehouse.provider_search for CCN-based community detection.';


--
-- Name: idx_place_of_service_normalized_phone; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_place_of_service_normalized_phone ON warehouse.place_of_service USING btree (normalized_phone) WHERE ((normalized_phone IS NOT NULL) AND (is_current = true));


--
-- Name: INDEX idx_place_of_service_normalized_phone; Type: COMMENT; Schema: warehouse; Owner: -
--

COMMENT ON INDEX warehouse.idx_place_of_service_normalized_phone IS 'B-tree index for CCN normalized_phone lookups.
Used in joins with warehouse.provider_search for CCN-based community detection.';


--
-- Name: idx_place_of_service_parent_ccn; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_place_of_service_parent_ccn ON warehouse.place_of_service USING btree (parent_ccn) WHERE ((parent_ccn IS NOT NULL) AND (is_current = true));


--
-- Name: idx_warehouse_community_created_at; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_community_created_at ON warehouse.community USING btree (created_at);


--
-- Name: idx_warehouse_community_current; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_community_current ON warehouse.community USING btree (npi, is_current) WHERE (is_current = true);


--
-- Name: idx_warehouse_community_effective_date; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_community_effective_date ON warehouse.community USING btree (effective_date);


--
-- Name: idx_warehouse_community_npi; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_community_npi ON warehouse.community USING btree (npi);


--
-- Name: idx_warehouse_community_npi_canonical_current_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_warehouse_community_npi_canonical_current_unique ON warehouse.community USING btree (npi, canonical_community_id) WHERE (is_current = true);


--
-- Name: idx_warehouse_community_npi_effective; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_community_npi_effective ON warehouse.community USING btree (npi, effective_date DESC);


--
-- Name: idx_warehouse_provider_created_at; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_created_at ON warehouse.provider USING btree (created_at);


--
-- Name: idx_warehouse_provider_current; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_current ON warehouse.provider USING btree (npi, is_current) WHERE (is_current = true);


--
-- Name: idx_warehouse_provider_effective_date; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_effective_date ON warehouse.provider USING btree (effective_date);


--
-- Name: idx_warehouse_provider_end_date_updates; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_end_date_updates ON warehouse.provider USING btree (npi, is_current, end_date, effective_date) WHERE (end_date IS NULL);


--
-- Name: idx_warehouse_provider_enum_type; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_enum_type ON warehouse.provider USING btree (enumeration_type);


--
-- Name: idx_warehouse_provider_hash; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_hash ON warehouse.provider USING btree (record_hash);


--
-- Name: idx_warehouse_provider_npi; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_npi ON warehouse.provider USING btree (npi);


--
-- Name: idx_warehouse_provider_npi_current_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_warehouse_provider_npi_current_unique ON warehouse.provider USING btree (npi) WHERE (is_current = true);


--
-- Name: idx_warehouse_provider_npi_is_current; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_npi_is_current ON warehouse.provider USING btree (npi, is_current);


--
-- Name: idx_warehouse_provider_npi_latest_record; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_npi_latest_record ON warehouse.provider USING btree (npi, effective_date DESC, created_at DESC);


--
-- Name: idx_warehouse_provider_source; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_warehouse_provider_source ON warehouse.provider USING btree (source_file);


--
-- PostgreSQL database dump complete
--

\unrestrict BzwZ8fzAGkZLZvpsrWGRe0vdpxe8vf6524ueI6QcH6gV6xBJUWAhvR6aox5pgGu

