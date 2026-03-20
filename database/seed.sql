-- FAA Knowledge Quiz — Seed Data

-- Categories
INSERT OR IGNORE INTO categories (name, label) VALUES ('written_exam',      'FAA Written Exam');
INSERT OR IGNORE INTO categories (name, label) VALUES ('checkride_oral',    'Checkride Oral');
INSERT OR IGNORE INTO categories (name, label) VALUES ('general_knowledge', 'General Knowledge');

-- Sources
INSERT OR IGNORE INTO sources (code, title, faa_number, url) VALUES
    ('PHAK', 'Pilot''s Handbook of Aeronautical Knowledge', 'FAA-H-8083-25B',
     'https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/phak');

INSERT OR IGNORE INTO sources (code, title, faa_number, url) VALUES
    ('AFH',  'Airplane Flying Handbook', 'FAA-H-8083-3C',
     'https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/airplane_handbook');

-- PHAK Chapters (17)
INSERT OR IGNORE INTO chapters (source_id, number, title) VALUES
    ((SELECT id FROM sources WHERE code='PHAK'),  1, 'Introduction to Flying'),
    ((SELECT id FROM sources WHERE code='PHAK'),  2, 'Aeronautical Decision-Making'),
    ((SELECT id FROM sources WHERE code='PHAK'),  3, 'Aircraft Construction'),
    ((SELECT id FROM sources WHERE code='PHAK'),  4, 'Principles of Flight'),
    ((SELECT id FROM sources WHERE code='PHAK'),  5, 'Aerodynamics of Flight'),
    ((SELECT id FROM sources WHERE code='PHAK'),  6, 'Flight Controls'),
    ((SELECT id FROM sources WHERE code='PHAK'),  7, 'Aircraft Systems'),
    ((SELECT id FROM sources WHERE code='PHAK'),  8, 'Flight Instruments'),
    ((SELECT id FROM sources WHERE code='PHAK'),  9, 'Flight Manuals and Other Documents'),
    ((SELECT id FROM sources WHERE code='PHAK'), 10, 'Weight and Balance'),
    ((SELECT id FROM sources WHERE code='PHAK'), 11, 'Aircraft Performance'),
    ((SELECT id FROM sources WHERE code='PHAK'), 12, 'Weather Theory'),
    ((SELECT id FROM sources WHERE code='PHAK'), 13, 'Aviation Weather Services'),
    ((SELECT id FROM sources WHERE code='PHAK'), 14, 'Airport Operations'),
    ((SELECT id FROM sources WHERE code='PHAK'), 15, 'Airspace'),
    ((SELECT id FROM sources WHERE code='PHAK'), 16, 'Navigation'),
    ((SELECT id FROM sources WHERE code='PHAK'), 17, 'Aeromedical Factors');

-- AFH Chapters (18)
INSERT OR IGNORE INTO chapters (source_id, number, title) VALUES
    ((SELECT id FROM sources WHERE code='AFH'),  1, 'Introduction to Flight Training'),
    ((SELECT id FROM sources WHERE code='AFH'),  2, 'Ground Operations'),
    ((SELECT id FROM sources WHERE code='AFH'),  3, 'Basic Flight Maneuvers'),
    ((SELECT id FROM sources WHERE code='AFH'),  4, 'Maintaining Aircraft Control: Upset Prevention and Recovery Training'),
    ((SELECT id FROM sources WHERE code='AFH'),  5, 'Takeoffs and Departure Climbs'),
    ((SELECT id FROM sources WHERE code='AFH'),  6, 'Ground Reference Maneuvers'),
    ((SELECT id FROM sources WHERE code='AFH'),  7, 'Airport Traffic Patterns'),
    ((SELECT id FROM sources WHERE code='AFH'),  8, 'Approaches and Landings'),
    ((SELECT id FROM sources WHERE code='AFH'),  9, 'Performance Maneuvers'),
    ((SELECT id FROM sources WHERE code='AFH'), 10, 'Night Operations'),
    ((SELECT id FROM sources WHERE code='AFH'), 11, 'Transition to Complex Airplanes'),
    ((SELECT id FROM sources WHERE code='AFH'), 12, 'Transition to Multiengine Airplanes'),
    ((SELECT id FROM sources WHERE code='AFH'), 13, 'Transition to Tailwheel Airplanes'),
    ((SELECT id FROM sources WHERE code='AFH'), 14, 'Transition to Turbopropeller-Powered Airplanes'),
    ((SELECT id FROM sources WHERE code='AFH'), 15, 'Transition to Jet-Powered Airplanes'),
    ((SELECT id FROM sources WHERE code='AFH'), 16, 'Transition to Light Sport Airplanes'),
    ((SELECT id FROM sources WHERE code='AFH'), 17, 'Emergency Procedures'),
    ((SELECT id FROM sources WHERE code='AFH'), 18, 'Glossary');
