-- =====================================================================
-- Shri Balaji Hostel: database schema for Supabase (PostgreSQL)
--
-- Converted from the desktop application's MS Access schema
-- (offbeatsoftware/hostelmanagement, HostelManagement/Data/DatabaseSchema.cs,
-- schema version 17). Same tables, columns, keys, unique rules and indexes.
--
-- Conversion rules
--   Access COUNTER              -> INTEGER GENERATED ALWAYS AS IDENTITY
--   TEXT(n)                     -> VARCHAR(n)
--   MEMO                        -> TEXT
--   CURRENCY                    -> NUMERIC(12,2)
--   BIT                         -> BOOLEAN
--   DATETIME, day only          -> DATE   (birth, admission, check in/out,
--                                          invoice, payment, refund, attendance)
--   DATETIME, moment in time    -> TIMESTAMPTZ (created, updated, sent, marked)
--   Names                       -> lower case with underscores (PostgreSQL style)
--
-- Run once on an empty database: Supabase Dashboard > SQL Editor > New query.
-- Everything runs in one transaction, so a failure leaves nothing behind.
-- =====================================================================

BEGIN;

-- Schema version, as in the desktop SchemaInfo table.
CREATE TABLE schema_info (
    version INTEGER NOT NULL
);
INSERT INTO schema_info (version) VALUES (17);

-- ---------------------------------------------------------------------
-- Hostels
-- ---------------------------------------------------------------------
CREATE TABLE hostel (
    hostel_id    INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_hostel PRIMARY KEY,
    hostel_name  VARCHAR(150) NOT NULL,
    address      VARCHAR(255),
    phone        VARCHAR(20),
    email        VARCHAR(150),
    created_date TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_date TIMESTAMPTZ,
    CONSTRAINT uq_hostel_hostel_name UNIQUE (hostel_name)
);

CREATE TABLE college (
    college_id   INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_college PRIMARY KEY,
    hostel_id    INTEGER      NOT NULL,
    college_name VARCHAR(150) NOT NULL,
    address      VARCHAR(255),
    phone        VARCHAR(20),
    CONSTRAINT uq_college_hostel_name UNIQUE (hostel_id, college_name),
    CONSTRAINT fk_college_hostel FOREIGN KEY (hostel_id) REFERENCES hostel (hostel_id)
);

-- A sharing type only decides how many students fit in a room.
CREATE TABLE sharing_type (
    sharing_type_id INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_sharing_type PRIMARY KEY,
    hostel_id       INTEGER     NOT NULL,
    sharing_name    VARCHAR(20) NOT NULL,
    capacity        INTEGER     NOT NULL,
    CONSTRAINT uq_sharing_type_hostel_name UNIQUE (hostel_id, sharing_name),
    CONSTRAINT fk_sharing_type_hostel FOREIGN KEY (hostel_id) REFERENCES hostel (hostel_id)
);

CREATE TABLE room (
    room_id         INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_room PRIMARY KEY,
    hostel_id       INTEGER     NOT NULL,
    room_number     VARCHAR(20) NOT NULL,
    floor           VARCHAR(20),
    sharing_type_id INTEGER     NOT NULL,
    gender          VARCHAR(10) NOT NULL,          -- Male / Female (shown as Boys / Girls)
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    remarks         VARCHAR(255),
    CONSTRAINT uq_room_hostel_number UNIQUE (hostel_id, room_number),
    CONSTRAINT fk_room_hostel FOREIGN KEY (hostel_id) REFERENCES hostel (hostel_id),
    CONSTRAINT fk_room_sharing_type FOREIGN KEY (sharing_type_id) REFERENCES sharing_type (sharing_type_id)
);

-- ---------------------------------------------------------------------
-- Students and room allocation
-- ---------------------------------------------------------------------
CREATE TABLE student (
    student_id        INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_student PRIMARY KEY,
    hostel_id         INTEGER      NOT NULL,
    student_name      VARCHAR(150) NOT NULL,
    date_of_birth     DATE,
    gender            VARCHAR(20),                 -- Male / Female / Other
    address           VARCHAR(255),
    college_id        INTEGER,
    course            VARCHAR(100),
    class_name        VARCHAR(50),
    mobile            VARCHAR(20),
    email             VARCHAR(150),
    father_name       VARCHAR(150),
    father_mobile     VARCHAR(20),
    father_email      VARCHAR(150),
    mother_name       VARCHAR(150),
    mother_mobile     VARCHAR(20),
    mother_email      VARCHAR(150),
    photo_path        VARCHAR(255),
    aadhaar_number    VARCHAR(12),
    aadhaar_card_path VARCHAR(255),
    admission_date    DATE         NOT NULL,
    status            VARCHAR(20)  NOT NULL,       -- Active / Left
    remarks           VARCHAR(255),
    CONSTRAINT fk_student_hostel FOREIGN KEY (hostel_id) REFERENCES hostel (hostel_id),
    CONSTRAINT fk_student_college FOREIGN KEY (college_id) REFERENCES college (college_id)
);
CREATE INDEX ix_student_student_name ON student (student_name);
CREATE INDEX ix_student_hostel_id    ON student (hostel_id);
CREATE INDEX ix_student_mobile       ON student (mobile);

-- History is kept: check out and transfer close an allocation.
CREATE TABLE room_allocation (
    allocation_id  INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_room_allocation PRIMARY KEY,
    student_id     INTEGER     NOT NULL,
    room_id        INTEGER     NOT NULL,
    check_in_date  DATE        NOT NULL,
    check_out_date DATE,
    status         VARCHAR(20) NOT NULL,           -- Current / Transferred / CheckedOut
    remarks        VARCHAR(255),
    bed_number     INTEGER,
    CONSTRAINT fk_room_allocation_student FOREIGN KEY (student_id) REFERENCES student (student_id),
    CONSTRAINT fk_room_allocation_room FOREIGN KEY (room_id) REFERENCES room (room_id)
);
CREATE INDEX ix_room_allocation_status ON room_allocation (status);

-- ---------------------------------------------------------------------
-- Fees: one invoice per student per academic year
-- (paid, pending and status are calculated from payments, not stored)
-- ---------------------------------------------------------------------
CREATE TABLE invoice (
    invoice_id       INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_invoice PRIMARY KEY,
    invoice_number   VARCHAR(30)   NOT NULL,
    student_id       INTEGER       NOT NULL,
    invoice_date     DATE          NOT NULL,
    academic_year    INTEGER       NOT NULL,
    room_rent        NUMERIC(12,2) NOT NULL,
    transport_amount NUMERIC(12,2) NOT NULL,
    remarks          VARCHAR(255),
    waived_amount    NUMERIC(12,2),
    CONSTRAINT uq_invoice_invoice_number UNIQUE (invoice_number),
    CONSTRAINT uq_invoice_student_year UNIQUE (student_id, academic_year),
    CONSTRAINT fk_invoice_student FOREIGN KEY (student_id) REFERENCES student (student_id)
);
CREATE INDEX ix_invoice_invoice_date ON invoice (invoice_date);

CREATE TABLE payment (
    payment_id     INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_payment PRIMARY KEY,
    receipt_number VARCHAR(30)   NOT NULL,
    student_id     INTEGER       NOT NULL,
    invoice_id     INTEGER       NOT NULL,
    payment_date   DATE          NOT NULL,
    amount         NUMERIC(12,2) NOT NULL,
    payment_method VARCHAR(30)   NOT NULL,         -- Cash / UPI / Bank transfer / Cheque
    reference      VARCHAR(100),
    remarks        VARCHAR(255),
    created_date   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_payment_receipt_number UNIQUE (receipt_number),
    CONSTRAINT fk_payment_student FOREIGN KEY (student_id) REFERENCES student (student_id),
    CONSTRAINT fk_payment_invoice FOREIGN KEY (invoice_id) REFERENCES invoice (invoice_id)
);
CREATE INDEX ix_payment_payment_date ON payment (payment_date);

-- Audit of edited and deleted payments (payment_id has no foreign key on
-- purpose: the payment row may have been deleted).
CREATE TABLE payment_change (
    payment_change_id INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_payment_change PRIMARY KEY,
    payment_id        INTEGER      NOT NULL,
    receipt_number    VARCHAR(30)  NOT NULL,
    student_id        INTEGER      NOT NULL,
    change_type       VARCHAR(10)  NOT NULL,       -- Edited / Deleted / Refund del
    changed_date      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    details           VARCHAR(255) NOT NULL,
    reason            VARCHAR(255),
    CONSTRAINT fk_payment_change_student FOREIGN KEY (student_id) REFERENCES student (student_id)
);
CREATE INDEX ix_payment_change_payment_id ON payment_change (payment_id);

-- Money paid back to a student; it also lowers the fee by the same amount.
CREATE TABLE refund (
    refund_id     INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_refund PRIMARY KEY,
    refund_number VARCHAR(30)   NOT NULL,
    student_id    INTEGER       NOT NULL,
    invoice_id    INTEGER       NOT NULL,
    refund_date   DATE          NOT NULL,
    amount        NUMERIC(12,2) NOT NULL,
    refund_method VARCHAR(30)   NOT NULL,          -- Cash / UPI / Bank transfer / Cheque
    reference     VARCHAR(100),
    reason        VARCHAR(255)  NOT NULL,
    created_date  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_refund_refund_number UNIQUE (refund_number),
    CONSTRAINT fk_refund_student FOREIGN KEY (student_id) REFERENCES student (student_id),
    CONSTRAINT fk_refund_invoice FOREIGN KEY (invoice_id) REFERENCES invoice (invoice_id)
);
CREATE INDEX ix_refund_refund_date ON refund (refund_date);

-- ---------------------------------------------------------------------
-- Emails and attendance
-- ---------------------------------------------------------------------
CREATE TABLE email_history (
    email_history_id INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_email_history PRIMARY KEY,
    student_id       INTEGER      NOT NULL,
    invoice_id       INTEGER,
    recipient_email  VARCHAR(150) NOT NULL,
    email_type       VARCHAR(30)  NOT NULL,        -- Invoice / Receipt / DueReminder / Absence
    subject          VARCHAR(255),
    sent_date        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    status           VARCHAR(20)  NOT NULL,        -- Sent / Failed
    error_message    VARCHAR(255),
    CONSTRAINT fk_email_history_student FOREIGN KEY (student_id) REFERENCES student (student_id),
    CONSTRAINT fk_email_history_invoice FOREIGN KEY (invoice_id) REFERENCES invoice (invoice_id)
);

CREATE TABLE attendance (
    attendance_id       INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_attendance PRIMARY KEY,
    student_id          INTEGER     NOT NULL,
    attendance_date     DATE        NOT NULL,
    is_present          BOOLEAN     NOT NULL,
    remarks             VARCHAR(255),
    marked_date         TIMESTAMPTZ NOT NULL DEFAULT now(),
    parent_emailed_date TIMESTAMPTZ,
    CONSTRAINT uq_attendance_student_date UNIQUE (student_id, attendance_date),
    CONSTRAINT fk_attendance_student FOREIGN KEY (student_id) REFERENCES student (student_id)
);
CREATE INDEX ix_attendance_attendance_date ON attendance (attendance_date);

-- ---------------------------------------------------------------------
-- Admin login and settings
-- ---------------------------------------------------------------------
-- password_hash is for the desktop sign in (salted PBKDF2). It is NULL for an
-- admin who signs in on the mobile app through Firebase; firebase_uid links
-- the row to the Firebase Authentication user.
CREATE TABLE admin_user (
    admin_user_id INTEGER GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_admin_user PRIMARY KEY,
    user_name     VARCHAR(50)  NOT NULL,
    password_hash VARCHAR(255),
    email         VARCHAR(150),
    phone         VARCHAR(20),
    firebase_uid  VARCHAR(128),
    created_date  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_date  TIMESTAMPTZ,
    CONSTRAINT uq_admin_user_user_name UNIQUE (user_name),
    CONSTRAINT uq_admin_user_firebase_uid UNIQUE (firebase_uid)
);
-- The user name is not case sensitive at sign in, as on the desktop.
CREATE UNIQUE INDEX ux_admin_user_user_name_lower ON admin_user (lower(user_name));

CREATE TABLE app_setting (
    setting_key   VARCHAR(50) CONSTRAINT pk_app_setting PRIMARY KEY,
    setting_value TEXT
);

-- ---------------------------------------------------------------------
-- Security: Supabase exposes tables in the public schema through its API.
-- Row Level Security with no policies blocks all access through the public
-- (anon) key until we add policies for the mobile app. The SQL Editor,
-- pgAdmin and the service role are not affected.
-- ---------------------------------------------------------------------
ALTER TABLE schema_info     ENABLE ROW LEVEL SECURITY;
ALTER TABLE hostel          ENABLE ROW LEVEL SECURITY;
ALTER TABLE college         ENABLE ROW LEVEL SECURITY;
ALTER TABLE sharing_type    ENABLE ROW LEVEL SECURITY;
ALTER TABLE room            ENABLE ROW LEVEL SECURITY;
ALTER TABLE student         ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_allocation ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice         ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment         ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_change  ENABLE ROW LEVEL SECURITY;
ALTER TABLE refund          ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_history   ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance      ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_user      ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_setting     ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------
-- Starting data
-- ---------------------------------------------------------------------
-- The admin who signs in on the mobile app (Firebase). Copy the User UID
-- from Firebase Console > Authentication > Users into firebase_uid later.
INSERT INTO admin_user (user_name, email)
VALUES ('admin', 'admin@shribalajihostel.com');

COMMIT;
