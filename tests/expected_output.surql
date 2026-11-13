-- schema
DEFINE TABLE OVERWRITE owner SCHEMAFULL;
DEFINE TABLE OVERWRITE vet SCHEMAFULL;
DEFINE TABLE OVERWRITE medication SCHEMAFULL;
DEFINE TABLE OVERWRITE patient SCHEMAFULL;
DEFINE TABLE OVERWRITE visit SCHEMAFULL;
DEFINE TABLE OVERWRITE treats TYPE RELATION IN vet OUT patient ENFORCED SCHEMAFULL;
DEFINE TABLE OVERWRITE note SCHEMAFULL;
DEFINE FIELD OVERWRITE address ON owner TYPE object;
DEFINE FIELD OVERWRITE address.city ON owner TYPE string;
DEFINE FIELD OVERWRITE address.line ON owner TYPE string;
DEFINE FIELD OVERWRITE address.zip ON owner TYPE option<string>;
DEFINE FIELD OVERWRITE email ON owner TYPE string ASSERT string::contains($value, '@') AND (!string::starts_with($value, '@'));
DEFINE FIELD OVERWRITE name ON owner TYPE string ASSERT $value != '';
DEFINE FIELD OVERWRITE phone ON owner TYPE option<string>;
DEFINE FIELD OVERWRITE referred_by ON owner TYPE option<record<owner>> REFERENCE ON DELETE UNSET ASSERT ($value = NONE OR (record::exists($value)));
DEFINE FIELD OVERWRITE tags ON owner TYPE array<string> DEFAULT [] ASSERT $value.all(|$item| $item != '');
DEFINE FIELD OVERWRITE contact ON vet TYPE object;
DEFINE FIELD OVERWRITE contact.email ON vet TYPE string ASSERT string::is_email($value);
DEFINE FIELD OVERWRITE contact.phone ON vet TYPE string;
DEFINE FIELD OVERWRITE license ON vet TYPE string READONLY ASSERT string::starts_with($value, 'VET-');
DEFINE FIELD OVERWRITE name ON vet TYPE string;
DEFINE FIELD OVERWRITE rate ON vet TYPE decimal ASSERT $value > 0.0dec;
DEFINE FIELD OVERWRITE specialty ON vet TYPE "Dental" | "General" | { kind: "Surgery", board: string };
DEFINE FIELD OVERWRITE years ON vet TYPE u8;
DEFINE FIELD OVERWRITE form ON medication TYPE string;
DEFINE FIELD OVERWRITE label ON medication TYPE string VALUE $this.name + ' (' + $this.form + ')';
DEFINE FIELD OVERWRITE name ON medication TYPE string;
DEFINE FIELD OVERWRITE stock ON medication TYPE i32 DEFAULT 0i32;
DEFINE FIELD OVERWRITE unit_price ON medication TYPE decimal;
DEFINE FIELD OVERWRITE age ON patient TYPE u8;
DEFINE FIELD OVERWRITE allergies ON patient TYPE array<record<medication>> DEFAULT [] REFERENCE ON DELETE UNSET ASSERT $value.all(|$e1| record::exists($e1));
DEFINE FIELD OVERWRITE chip ON patient TYPE option<object>;
DEFINE FIELD OVERWRITE chip.code ON patient TYPE string;
DEFINE FIELD OVERWRITE chip.implanted_by ON patient TYPE record<vet> ASSERT record::exists($value);
DEFINE FIELD OVERWRITE name ON patient TYPE string;
DEFINE FIELD OVERWRITE owner ON patient TYPE record<owner> REFERENCE ON DELETE CASCADE ASSERT record::exists($value);
DEFINE FIELD OVERWRITE species ON patient TYPE { kind: "Bird", wingspan_cm: u8 } | "Cat" | "Dog" | { kind: "Exotic", latin: string } ASSERT (IF $value.kind = 'Bird' THEN $value.wingspan_cm > 0 ELSE true END);
DEFINE FIELD OVERWRITE vaccines ON patient TYPE array<{ given: string, name: string, vet: record<vet> }>;
DEFINE FIELD OVERWRITE vaccines[*].name ON patient ASSERT $value != '';
DEFINE FIELD OVERWRITE vaccines[*].vet ON patient ASSERT record::exists($value);
DEFINE FIELD OVERWRITE weight_kg ON patient TYPE decimal ASSERT $value > 0.0dec;
DEFINE FIELD OVERWRITE fee ON visit TYPE decimal ASSERT (($this.items.len() = 0) OR ($value > 0.0dec)) AND ($value >= 0.0dec);
DEFINE FIELD OVERWRITE items ON visit TYPE array<{ doses: int, medication: record<medication> }>;
DEFINE FIELD OVERWRITE items[*].doses ON visit ASSERT $value > 0;
DEFINE FIELD OVERWRITE items[*].medication ON visit ASSERT record::exists($value);
DEFINE FIELD OVERWRITE outcome ON visit TYPE { kind: "Followup", days: u8 } | { kind: "Referred", reason: string, to: record<vet> } | "Treated" ASSERT ((IF $value.kind = 'Referred' THEN record::exists($value.to) ELSE true END)) AND ((IF $value.kind = 'Followup' THEN ($value.days > 0) AND ($value.days <= 90) ELSE true END));
DEFINE FIELD OVERWRITE patient ON visit TYPE record<patient> REFERENCE ON DELETE CASCADE ASSERT record::exists($value);
DEFINE FIELD OVERWRITE seen ON visit TYPE datetime;
DEFINE FIELD OVERWRITE vet ON visit TYPE record<vet> REFERENCE ON DELETE REJECT ASSERT record::exists($value);
DEFINE FIELD OVERWRITE primary ON treats TYPE bool;
DEFINE FIELD OVERWRITE since_year ON treats TYPE int ASSERT $value >= 1990;
DEFINE FIELD OVERWRITE id ON note TYPE string DEFAULT rand::ulid();
DEFINE FIELD OVERWRITE text ON note TYPE string;
DEFINE FIELD OVERWRITE vet ON note TYPE record<vet> REFERENCE ON DELETE REJECT ASSERT record::exists($value);
DEFINE INDEX OVERWRITE owner_email_unique ON owner FIELDS email UNIQUE;
DEFINE INDEX OVERWRITE owner_address_city_address_line_unique ON owner FIELDS address.city, address.line UNIQUE;
DEFINE INDEX OVERWRITE owner_address_city_index ON owner FIELDS address.city;
DEFINE INDEX OVERWRITE vet_contact_email_unique ON vet FIELDS contact.email UNIQUE;
DEFINE INDEX OVERWRITE patient_name_owner_unique ON patient FIELDS name, owner UNIQUE;
DEFINE INDEX OVERWRITE patient_age_index ON patient FIELDS age;
DEFINE INDEX OVERWRITE patient_chip_implanted_by_link ON patient FIELDS chip.implanted_by;
DEFINE INDEX OVERWRITE patient_vaccines_vet_link ON patient FIELDS vaccines[*].vet;
DEFINE INDEX OVERWRITE visit_seen_index ON visit FIELDS seen;
DEFINE INDEX OVERWRITE visit_items_medication_link ON visit FIELDS items[*].medication;
DEFINE INDEX OVERWRITE treats_in_out_unique ON treats FIELDS in, out UNIQUE;
DEFINE EVENT OVERWRITE patient_chip_implanted_by_on_delete ON vet WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM patient WHERE chip.implanted_by = $before.id LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by patient.chip.implanted_by' } };
DEFINE EVENT OVERWRITE patient_vaccines_vet_on_delete ON vet WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM patient WHERE $before.id IN vaccines[*].vet LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by patient.vaccines[*].vet' } };
DEFINE EVENT OVERWRITE visit_items_medication_on_delete ON medication WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM visit WHERE $before.id IN items[*].medication LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by visit.items[*].medication' } };
DEFINE EVENT OVERWRITE visit_outcome_Referred_to_on_delete ON vet WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM visit WHERE (outcome.kind = 'Referred' AND outcome.to = $before.id) LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by visit.outcome.to' } };

-- seed: vet
-- vars: a1625f3183a767636f6e74616374a265656d61696c717275746840706177732e6578616d706c656570686f6e65683535352d303130316269646472757468676c6963656e7365685645542d31303031646e616d656b52757468204f6b61666f726472617465ca6438302e30697370656369616c74796747656e6572616c657965617273d8b50ca767636f6e74616374a265656d61696c7073616d40706177732e6578616d706c656570686f6e65683535352d303130326269646373616d676c6963656e7365685645542d31303032646e616d656a53616d20506574726f766472617465ca653134302e30697370656369616c7479a2646b696e64675375726765727965626f6172646441435653657965617273d8b508a767636f6e74616374a265656d61696c7074696140706177732e6578616d706c656570686f6e65683535352d3031303362696463746961676c6963656e7365685645542d31303033646e616d656a546961204272616e64746472617465ca6439352e35697370656369616c74796644656e74616c657965617273d8b503
BEGIN;
INSERT INTO vet $_1 RETURN AFTER;
COMMIT;

-- seed: owner
-- vars: a1625f3184a56761646472657373a36463697479644f736c6f646c696e656a53746f72676174612034637a6970643031353565656d61696c6f6a6f6e406578616d706c652e6f7267626964636a6f6e646e616d65684a6f6e2042657267647461677381636e6577a66761646472657373a26463697479644c796f6e646c696e656e527565204d65726369657265203965656d61696c706c656e61406578616d706c652e6f7267626964646c656e61646e616d65694c656e6120526f75786570686f6e65683535352d30313838647461677380a66761646472657373a36463697479644f736c6f646c696e656c416b65727367617461203132637a6970643031353865656d61696c706d617261406578616d706c652e6f7267626964646d617261646e616d65684d6172612049746f6570686f6e65683535352d3031343264746167738163766970a66761646472657373a2646369747965506f72746f646c696e65705275612064617320466c6f726573203765656d61696c706e6f6f72406578616d706c652e6f7267626964646e6f6f72646e616d656b4e6f6f72204861646461646b72656665727265645f6279c882656f776e6572646d61726164746167738263766970636e6577
BEGIN;
INSERT INTO owner $_1 RETURN AFTER;
COMMIT;

-- seed: medication
-- vars: a1625f3184a664666f726d667461626c65746269646b616d6f786963696c6c696e656c6162656c74416d6f786963696c6c696e20287461626c657429646e616d656b416d6f786963696c6c696e6573746f636bd8b818c86a756e69745f7072696365ca63302e38a664666f726d667461626c6574626964676173706972696e656c6162656c704173706972696e20287461626c657429646e616d65674173706972696e6573746f636bd8b81901f46a756e69745f7072696365ca63302e32a664666f726d6763617073756c656269646a6761626170656e74696e656c6162656c744761626170656e74696e202863617073756c6529646e616d656a4761626170656e74696e6573746f636bd8b818286a756e69745f7072696365ca63312e34a664666f726d69696e6a656374696f6e6269646a697665726d656374696e656c6162656c76497665726d656374696e2028696e6a656374696f6e29646e616d656a497665726d656374696e6573746f636bd8b80f6a756e69745f7072696365ca63332e35
BEGIN;
INSERT INTO medication $_1 RETURN AFTER;
COMMIT;

-- seed: patient
-- vars: a1625f3186a863616765d8b50c69616c6c6572676965738062696462626f646e616d6562426f656f776e6572c882656f776e6572636a6f6e677370656369657363446f676876616363696e657381a365676976656e6a323032352d30352d3032646e616d656672616269657363766574c882637665746472757468697765696768745f6b67ca6433312e35a863616765d8b50269616c6c65726769657380626964646b697769646e616d65644b697769656f776e6572c882656f776e6572646c656e616773706563696573a2646b696e6464426972646b77696e677370616e5f636dd8b518196876616363696e657380697765696768745f6b67ca63302e34a963616765d8b50369616c6c65726769657381c8826a6d656469636174696f6e676173706972696e6463686970a264636f6465673938352d3131326c696d706c616e7465645f6279c882637665746373616d626964646c756e61646e616d65644c756e61656f776e6572c882656f776e6572646d6172616773706563696573634361746876616363696e657380697765696768745f6b67ca63342e32a863616765d8b50969616c6c65726769657380626964646d696d69646e616d65644d696d69656f776e6572c882656f776e6572646e6f6f726773706563696573634361746876616363696e657380697765696768745f6b67ca63352e31a963616765d8b50569616c6c65726769657382c8826a6d656469636174696f6e676173706972696ec8826a6d656469636174696f6e6b616d6f786963696c6c696e6463686970a264636f6465673938352d3130306c696d706c616e7465645f6279c88263766574647275746862696463726578646e616d6563526578656f776e6572c882656f776e6572646d617261677370656369657363446f676876616363696e657382a365676976656e6a323032352d30362d3131646e616d656672616269657363766574c882637665746472757468a365676976656e6a323032352d30362d3131646e616d656964697374656d70657263766574c882637665746373616d697765696768745f6b67ca6432382e30a863616765d8b50469616c6c65726769657380626964637a6564646e616d65635a6564656f776e6572c882656f776e6572646e6f6f726773706563696573a2646b696e646645786f746963656c6174696e656765636b6f6876616363696e657380697765696768745f6b67ca63302e31
BEGIN;
INSERT INTO patient $_1 RETURN AFTER;
COMMIT;

-- seed: visit
-- vars: a1625f3187a763666565ca6438302e30626964627631656974656d7381a265646f7365730e6a6d656469636174696f6ec8826a6d656469636174696f6e6b616d6f786963696c6c696e676f7574636f6d6567547265617465646770617469656e74c8826770617469656e7463726578647365656ecc821a696215100063766574c882637665746472757468a763666565ca653134302e30626964627632656974656d7380676f7574636f6d65a2646b696e6468466f6c6c6f7775706464617973d8b50e6770617469656e74c8826770617469656e7463726578647365656ecc821a698206680063766574c882637665746373616da763666565ca6438302e30626964627633656974656d7381a265646f7365730a6a6d656469636174696f6ec8826a6d656469636174696f6e6a6761626170656e74696e676f7574636f6d65a3646b696e6468526566657272656466726561736f6e6c64656e74616c207363616c6562746fc88263766574637469616770617469656e74c8826770617469656e74646c756e61647365656ecc821a699834240063766574c882637665746472757468a763666565ca6438302e30626964627634656974656d7382a265646f736573076a6d656469636174696f6ec8826a6d656469636174696f6e6b616d6f786963696c6c696ea265646f736573016a6d656469636174696f6ec8826a6d656469636174696f6e6a697665726d656374696e676f7574636f6d6567547265617465646770617469656e74c8826770617469656e7462626f647365656ecc821a69a962300063766574c882637665746472757468a763666565ca653134302e30626964627635656974656d7380676f7574636f6d6567547265617465646770617469656e74c8826770617469656e74646d696d69647365656ecc821a69bad68c0063766574c882637665746373616da763666565ca6434302e30626964627636656974656d7381a265646f736573016a6d656469636174696f6ec8826a6d656469636174696f6e6a697665726d656374696e676f7574636f6d65a2646b696e6468466f6c6c6f7775706464617973d8b5076770617469656e74c8826770617469656e74646b697769647365656ecc821a69ce29080063766574c882637665746472757468a763666565ca6436302e30626964627637656974656d7380676f7574636f6d6567547265617465646770617469656e74c8826770617469656e74637a6564647365656ecc821a69da45d00063766574c882637665746373616d
BEGIN;
INSERT INTO visit $_1 RETURN AFTER;
COMMIT;

-- seed: treats
-- vars: a1625f3188a562696ec882637665746472757468626964626531677072696d617279f56a73696e63655f796561721907e6636f7574c8826770617469656e7463726578a562696ec882637665746373616d626964626532677072696d617279f46a73696e63655f796561721907e8636f7574c8826770617469656e7463726578a562696ec882637665746472757468626964626533677072696d617279f56a73696e63655f796561721907e4636f7574c8826770617469656e7462626fa562696ec882637665746373616d626964626534677072696d617279f56a73696e63655f796561721907e9636f7574c8826770617469656e74646c756e61a562696ec8826376657463746961626964626535677072696d617279f46a73696e63655f796561721907e9636f7574c8826770617469656e74646c756e61a562696ec882637665746472757468626964626536677072696d617279f56a73696e63655f796561721907ea636f7574c8826770617469656e74646b697769a562696ec882637665746373616d626964626537677072696d617279f56a73696e63655f796561721907e7636f7574c8826770617469656e74646d696d69a562696ec882637665746472757468626964626538677072696d617279f56a73696e63655f796561721907ea636f7574c8826770617469656e74637a6564
BEGIN;
INSERT RELATION INTO treats $_1 RETURN AFTER;
COMMIT;

-- query: owners_in_city
-- ordered
-- roc: [{ id: 'jon', name: 'Jon Berg', phone: 'none' }, { id: 'mara', name: 'Mara Ito', phone: '555-0142' }]
-- vars: a16463697479644f736c6f
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone FROM owner WHERE address.city = $city ORDER BY id;
-- script
LET $city = 'Oslo';
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone FROM owner WHERE address.city = $city ORDER BY id;

-- query: vip_owners
-- roc: [{ id: 'mara', name: 'Mara Ito', phone: '555-0142' }, { id: 'noor', name: 'Noor Haddad', phone: 'none' }]
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone FROM owner WHERE tags CONTAINS 'vip';

-- query: referrals
-- roc: [{ by: 'Mara Ito', id: 'noor' }]
SELECT referred_by.name ?? 'nobody' AS by, record::id(id) AS id FROM owner WHERE referred_by IS NOT NONE;

-- query: pet_roster
-- ordered
-- roc: [{ id: 'bo', kind: 'dog', owner: 'Jon Berg' }, { id: 'kiwi', kind: 'bird', owner: 'Lena Roux' }, { id: 'luna', kind: 'cat', owner: 'Mara Ito' }, { id: 'mimi', kind: 'cat', owner: 'Noor Haddad' }, { id: 'rex', kind: 'dog', owner: 'Mara Ito' }, { id: 'zed', kind: 'gecko', owner: 'Noor Haddad' }]
SELECT record::id(id) AS id, (IF species.kind = 'Bird' THEN 'bird' ELSE IF species = 'Cat' THEN 'cat' ELSE IF species = 'Dog' THEN 'dog' ELSE species.latin END) AS kind, owner.name AS owner FROM patient ORDER BY id;

-- query: vet_at_key
-- roc: [{ id: 'ruth', specialty: 'General', years: 12u8 }]
SELECT record::id(id) AS id, specialty AS specialty, years AS years FROM vet:⟨ruth⟩;

-- query: vet_by_key
-- roc: [{ id: 'ruth', specialty: 'General', years: 12u8 }]
-- vars: a1636b65796472757468
SELECT record::id(id) AS id, specialty AS specialty, years AS years FROM vet WHERE id = type::record('vet', $key);
-- script
LET $key = 'ruth';
SELECT record::id(id) AS id, specialty AS specialty, years AS years FROM vet WHERE id = type::record('vet', $key);

-- query: wide_winged
-- roc: ['Kiwi']
SELECT VALUE name FROM patient WHERE (IF species.kind = 'Bird' THEN species.wingspan_cm >= 20 ELSE false END);

-- query: chips
-- roc: [{ by: 'nobody', chip: 'none', id: 'bo' }, { by: 'nobody', chip: 'none', id: 'kiwi' }, { by: 'Sam Petrov', chip: '985-112', id: 'luna' }, { by: 'nobody', chip: 'none', id: 'mimi' }, { by: 'Ruth Okafor', chip: '985-100', id: 'rex' }, { by: 'nobody', chip: 'none', id: 'zed' }]
SELECT chip.implanted_by.name ?? 'nobody' AS by, chip.code ?? 'none' AS chip, record::id(id) AS id FROM patient;

-- query: vaccinated_by_ruth
-- roc: [{ id: 'bo', vets: ['Ruth Okafor'] }, { id: 'rex', vets: ['Ruth Okafor', 'Sam Petrov'] }]
SELECT record::id(id) AS id, vaccines.map(|$v1| $v1.vet.name) AS vets FROM patient WHERE vet:⟨ruth⟩ IN vaccines[*].vet;

-- query: recent_visits
-- ordered
-- roc: [{ bill: 89.1dec, id: 'v4', patient: 'Bo', vet: 'Ruth Okafor' }, { bill: 140.0dec, id: 'v5', patient: 'Mimi', vet: 'Sam Petrov' }, { bill: 43.5dec, id: 'v6', patient: 'Kiwi', vet: 'Ruth Okafor' }, { bill: 60.0dec, id: 'v7', patient: 'Zed', vet: 'Sam Petrov' }]
-- vars: a16573696e6365cc821a69a3818000
SELECT fee + math::sum(items.map(|$v1| <decimal>$v1.doses * $v1.medication.unit_price)) AS bill, record::id(id) AS id, patient.name AS patient, vet.name AS vet FROM visit WHERE $since <= seen ORDER BY id;
-- script
LET $since = d'2026-03-01T00:00:00Z';
SELECT fee + math::sum(items.map(|$v1| <decimal>$v1.doses * $v1.medication.unit_price)) AS bill, record::id(id) AS id, patient.name AS patient, vet.name AS vet FROM visit WHERE $since <= seen ORDER BY id;

-- query: past_visits
-- roc: ['v1', 'v2', 'v3', 'v4', 'v5', 'v6', 'v7']
SELECT VALUE record::id(id) FROM visit WHERE seen < time::now();

-- query: follow_ups
-- roc: [{ id: 'v2', text: 'follow-up' }, { id: 'v3', text: 'referred to Tia Brandt' }, { id: 'v6', text: 'follow-up' }]
SELECT record::id(id) AS id, (IF outcome.kind = 'Followup' THEN 'follow-up' ELSE IF outcome.kind = 'Referred' THEN 'referred to ' + outcome.to.name ELSE 'treated' END) AS text FROM visit WHERE outcome != 'Treated';

-- query: case_load
-- roc: [{ name: 'Ruth Okafor', patients: 4u64, primary: 4u64 }, { name: 'Sam Petrov', patients: 3u64, primary: 2u64 }, { name: 'Tia Brandt', patients: 1u64, primary: 0u64 }]
SELECT name AS name, ->treats.len() AS patients, ->treats[WHERE primary].len() AS primary FROM vet;

-- query: teams
-- roc: [{ lead: ['Ruth Okafor'], name: 'Bo', team: 1u64 }, { lead: ['Ruth Okafor'], name: 'Kiwi', team: 1u64 }, { lead: ['Sam Petrov'], name: 'Luna', team: 2u64 }, { lead: ['Sam Petrov'], name: 'Mimi', team: 1u64 }, { lead: ['Ruth Okafor'], name: 'Rex', team: 2u64 }, { lead: ['Ruth Okafor'], name: 'Zed', team: 1u64 }]
SELECT <-treats[WHERE primary]<-vet.name AS lead, name AS name, <-treats.len() AS team FROM patient;

-- query: ledger
-- ordered
-- roc: [{ avg_fee: 113.33333333333333f, revenue: 340.0dec, vet: 'Sam Petrov', visits: 3u64 }, { avg_fee: 70f, revenue: 280.0dec, vet: 'Ruth Okafor', visits: 4u64 }]
SELECT math::mean(<float>fee) AS avg_fee, math::sum(fee) AS revenue, vet.name AS vet, count() AS visits FROM visit GROUP BY vet ORDER BY revenue DESC LIMIT 2;

-- query: eldest
-- ordered
-- roc: [{ age: 12u8, id: 'bo' }, { age: 9u8, id: 'mimi' }, { age: 5u8, id: 'rex' }]
SELECT age AS age, record::id(id) AS id FROM patient ORDER BY age DESC LIMIT 3;

-- query: labels
-- ordered
-- roc: ['Amoxicillin (tablet)', 'Aspirin (tablet)', 'Gabapentin (capsule)', 'Ivermectin (injection)']
SELECT VALUE label FROM medication ORDER BY label;

-- query: whole_vets
-- roc: [{ contact: { email: 'ruth@paws.example', phone: '555-0101' }, id: 'ruth', license: 'VET-1001', name: 'Ruth Okafor', rate: 80.0dec, specialty: 'General', years: 12u8 }, { contact: { email: 'sam@paws.example', phone: '555-0102' }, id: 'sam', license: 'VET-1002', name: 'Sam Petrov', rate: 140.0dec, specialty: { kind: 'Surgery', board: 'ACVS' }, years: 8u8 }, { contact: { email: 'tia@paws.example', phone: '555-0103' }, id: 'tia', license: 'VET-1003', name: 'Tia Brandt', rate: 95.5dec, specialty: 'Dental', years: 3u8 }]
SELECT contact, record::id(id) AS id, license, name, rate, specialty, years FROM vet;

-- query: second_page
-- ordered
-- roc: [{ id: 'luna', kind: 'cat', owner: 'Mara Ito' }, { id: 'mimi', kind: 'cat', owner: 'Noor Haddad' }]
SELECT record::id(id) AS id, (IF species.kind = 'Bird' THEN 'bird' ELSE IF species = 'Cat' THEN 'cat' ELSE IF species = 'Dog' THEN 'dog' ELSE species.latin END) AS kind, owner.name AS owner FROM patient ORDER BY id LIMIT 2 START 2;

-- query: linked_fields
-- roc: [{ city: 'Oslo', id: 'bo', vets: ['Ruth Okafor'] }, { city: 'Lyon', id: 'kiwi', vets: [] }, { city: 'Oslo', id: 'luna', vets: [] }, { city: 'Porto', id: 'mimi', vets: [] }, { city: 'Oslo', id: 'rex', vets: ['Ruth Okafor', 'Sam Petrov'] }, { city: 'Porto', id: 'zed', vets: [] }]
SELECT owner.address.city AS city, record::id(id) AS id, vaccines.map(|$v1| $v1.vet.name) AS vets FROM patient;

-- query: linked_rows
-- roc: [{ id: 'bo', owner: { address: { city: 'Oslo', line: 'Storgata 4', zip: '0155' }, email: 'jon@example.org', id: 'jon', name: 'Jon Berg', tags: ['new'] }, vets: [{ contact: { email: 'ruth@paws.example', phone: '555-0101' }, id: 'ruth', license: 'VET-1001', name: 'Ruth Okafor', rate: 80.0dec, specialty: 'General', years: 12u8 }] }, { id: 'kiwi', owner: { address: { city: 'Lyon', line: 'Rue Merciere 9' }, email: 'lena@example.org', id: 'lena', name: 'Lena Roux', phone: '555-0188', tags: [] }, vets: [] }, { id: 'luna', owner: { address: { city: 'Oslo', line: 'Akersgata 12', zip: '0158' }, email: 'mara@example.org', id: 'mara', name: 'Mara Ito', phone: '555-0142', tags: ['vip'] }, vets: [] }, { id: 'mimi', owner: { address: { city: 'Porto', line: 'Rua das Flores 7' }, email: 'noor@example.org', id: 'noor', name: 'Noor Haddad', referred_by: owner:⟨mara⟩, tags: ['vip', 'new'] }, vets: [] }, { id: 'rex', owner: { address: { city: 'Oslo', line: 'Akersgata 12', zip: '0158' }, email: 'mara@example.org', id: 'mara', name: 'Mara Ito', phone: '555-0142', tags: ['vip'] }, vets: [{ contact: { email: 'ruth@paws.example', phone: '555-0101' }, id: 'ruth', license: 'VET-1001', name: 'Ruth Okafor', rate: 80.0dec, specialty: 'General', years: 12u8 }, { contact: { email: 'sam@paws.example', phone: '555-0102' }, id: 'sam', license: 'VET-1002', name: 'Sam Petrov', rate: 140.0dec, specialty: { kind: 'Surgery', board: 'ACVS' }, years: 8u8 }] }, { id: 'zed', owner: { address: { city: 'Porto', line: 'Rua das Flores 7' }, email: 'noor@example.org', id: 'noor', name: 'Noor Haddad', referred_by: owner:⟨mara⟩, tags: ['vip', 'new'] }, vets: [] }]
SELECT record::id(id) AS id, owner.{ address, email, id: record::id(id), name, phone, referred_by, tags } AS owner, vaccines.map(|$v1| $v1.vet.{ contact, id: record::id(id), license, name, rate, specialty, years }) AS vets FROM patient;

-- query: cheaper_than
-- roc: [{ form: 'tablet', id: 'amoxicillin', label: 'Amoxicillin (tablet)', name: 'Amoxicillin', stock: 200i32, unit_price: 0.8dec }, { form: 'tablet', id: 'aspirin', label: 'Aspirin (tablet)', name: 'Aspirin', stock: 500i32, unit_price: 0.2dec }]
-- vars: a1625f31ca63302e39
SELECT form, record::id(id) AS id, label, name, stock, unit_price FROM medication WHERE unit_price < $_1;
-- script
LET $_1 = 0.9dec;
SELECT form, record::id(id) AS id, label, name, stock, unit_price FROM medication WHERE unit_price < $_1;

-- query: owners_at
-- roc: [{ address: { city: 'Oslo', line: 'Storgata 4', zip: '0155' }, email: 'jon@example.org', id: 'jon', name: 'Jon Berg', tags: ['new'] }, { address: { city: 'Lyon', line: 'Rue Merciere 9' }, email: 'lena@example.org', id: 'lena', name: 'Lena Roux', phone: '555-0188', tags: [] }]
-- vars: a1625f3182a26463697479644c796f6e646c696e656e527565204d657263696572652039a36463697479644f736c6f646c696e656a53746f72676174612034637a69706430313535
SELECT address, email, record::id(id) AS id, name, phone, referred_by, tags FROM owner WHERE address IN $_1;
-- script
LET $_1 = [{ city: 'Lyon', line: 'Rue Merciere 9' }, { city: 'Oslo', line: 'Storgata 4', zip: '0155' }];
SELECT address, email, record::id(id) AS id, name, phone, referred_by, tags FROM owner WHERE address IN $_1;

-- query: owner_at, with a zip
-- roc: [{ address: { city: 'Oslo', line: 'Storgata 4', zip: '0155' }, email: 'jon@example.org', id: 'jon', name: 'Jon Berg', tags: ['new'] }]
-- vars: a1625f31a36463697479644f736c6f646c696e656a53746f72676174612034637a69706430313535
SELECT address, email, record::id(id) AS id, name, phone, referred_by, tags FROM owner WHERE (address.city = $_1.city) AND (address.line = $_1.line) AND (address.zip = $_1.zip);
-- script
LET $_1 = { city: 'Oslo', line: 'Storgata 4', zip: '0155' };
SELECT address, email, record::id(id) AS id, name, phone, referred_by, tags FROM owner WHERE (address.city = $_1.city) AND (address.line = $_1.line) AND (address.zip = $_1.zip);

-- query: owner_at, with no zip
-- roc: [{ address: { city: 'Lyon', line: 'Rue Merciere 9' }, email: 'lena@example.org', id: 'lena', name: 'Lena Roux', phone: '555-0188', tags: [] }]
-- vars: a1625f31a26463697479644c796f6e646c696e656e527565204d657263696572652039
SELECT address, email, record::id(id) AS id, name, phone, referred_by, tags FROM owner WHERE (address.city = $_1.city) AND (address.line = $_1.line) AND (address.zip = $_1.zip);
-- script
LET $_1 = { city: 'Lyon', line: 'Rue Merciere 9' };
SELECT address, email, record::id(id) AS id, name, phone, referred_by, tags FROM owner WHERE (address.city = $_1.city) AND (address.line = $_1.line) AND (address.zip = $_1.zip);

-- query: primary_owners
-- intrinsic: owners
-- roc: [{ name: 'Ruth Okafor', owners: ['Mara Ito', 'Jon Berg', 'Lena Roux', 'Noor Haddad'] }, { name: 'Sam Petrov', owners: ['Mara Ito', 'Noor Haddad'] }, { name: 'Tia Brandt', owners: [] }]
SELECT name AS name, ->treats[WHERE primary]->patient.owner.name AS owners FROM vet;

-- query: lead_patients
-- intrinsic: patients
-- roc: [{ name: 'Bo', patients: ['Rex', 'Bo', 'Kiwi', 'Zed'] }, { name: 'Kiwi', patients: ['Rex', 'Bo', 'Kiwi', 'Zed'] }, { name: 'Luna', patients: ['Rex', 'Luna', 'Mimi'] }, { name: 'Mimi', patients: ['Rex', 'Luna', 'Mimi'] }, { name: 'Rex', patients: ['Rex', 'Bo', 'Kiwi', 'Zed'] }, { name: 'Zed', patients: ['Rex', 'Bo', 'Kiwi', 'Zed'] }]
SELECT name AS name, <-treats[WHERE primary]<-vet->treats->patient.name AS patients FROM patient;

-- query: treats_for_oslo
-- roc: ['Ruth Okafor', 'Sam Petrov']
SELECT VALUE name FROM vet WHERE ->treats[WHERE primary]->patient.owner.address.city CONTAINS 'Oslo';

-- rejects: check_as_assert
-- error: field `weight_kg`
-- vars: a2625f31c8826770617469656e7463626164625f32a763616765d8b50c69616c6c65726769657380646e616d656d46656174686572776569676874656f776e6572c882656f776e6572636a6f6e677370656369657363446f676876616363696e657381a365676976656e6a323032352d30352d3032646e616d656672616269657363766574c882637665746472757468697765696768745f6b67ca63302e30
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: check_over_two_fields
-- error: field `fee`
-- vars: a2625f31c882657669736974627638625f32a663666565ca63302e30656974656d7381a265646f7365730e6a6d656469636174696f6ec8826a6d656469636174696f6e6b616d6f786963696c6c696e676f7574636f6d6567547265617465646770617469656e74c8826770617469656e7463726578647365656ecc821a696215100063766574c882637665746472757468
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: check_over_two_fields_on_update
-- error: field `fee`
UPDATE visit:⟨v1⟩ SET fee = 0.0dec RETURN AFTER;

-- rejects: assert_email
-- error: field `email`
-- vars: a2625f31c882656f776e657263626164625f32a46761646472657373a26463697479674e6f7768657265646c696e656932204d61696e20537465656d61696c746d61696c6c6573732e6578616d706c652e6f7267646e616d65684d61696c6c657373647461677381636e6577
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: assert_on_nested_path
-- error: field `contact.email`
-- vars: a2625f31c8826376657463626164625f32a667636f6e74616374a265656d61696c6a6e6f2d61742d7369676e6570686f6e656131676c6963656e7365685645542d39303031646e616d656a53616d20506574726f766472617465ca653134302e30697370656369616c7479a2646b696e64675375726765727965626f6172646441435653657965617273d8b508
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: assert_on_union
-- error: field `species`
-- vars: a2625f31c8826770617469656e7463626164625f32a763616765d8b50269616c6c65726769657380646e616d656857696e676c657373656f776e6572c882656f776e6572646c656e616773706563696573a2646b696e6464426972646b77696e677370616e5f636dd8b5006876616363696e657380697765696768745f6b67ca63302e34
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: assert_on_outcome
-- error: field `outcome`
-- vars: a2625f31c88265766973697463626164625f32a663666565ca653134302e30656974656d7380676f7574636f6d65a2646b696e6468466f6c6c6f7775706464617973d8b5006770617469656e74c8826770617469656e7463726578647365656ecc821a698206680063766574c882637665746373616d
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: assert_each_tag
-- error: field `tags`
-- vars: a2625f31c882656f776e657263626164625f32a46761646472657373a26463697479674e6f7768657265646c696e656931204d61696e20537465656d61696c71626c616e6b406578616d706c652e6f7267646e616d6565426c616e6b64746167738160
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: assert_each_dose
-- error: field `items.*.doses`
-- vars: a2625f31c88265766973697463626164625f32a663666565ca6438302e30656974656d7381a265646f736573006a6d656469636174696f6ec8826a6d656469636174696f6e6b616d6f786963696c6c696e676f7574636f6d6567547265617465646770617469656e74c8826770617469656e7463726578647365656ecc821a696215100063766574c882637665746472757468
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: assert_each_vaccine
-- error: field `vaccines.*.name`
-- vars: a2625f31c8826770617469656e7463626164625f32a763616765d8b50c69616c6c65726769657380646e616d6567556e6e616d6564656f776e6572c882656f776e6572636a6f6e677370656369657363446f676876616363696e657381a365676976656e6a323032352d30312d3031646e616d656063766574c882637665746472757468697765696768745f6b67ca6433312e35
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: unique_nested_path
-- error: already contains
-- vars: a2625f31c8826376657463626164625f32a667636f6e74616374a265656d61696c7073616d40706177732e6578616d706c656570686f6e65683535352d30313032676c6963656e7365685645542d39303031646e616d656a53616d20506574726f766472617465ca653134302e30697370656369616c7479a2646b696e64675375726765727965626f6172646441435653657965617273d8b508
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: unique_composite_with_link
-- error: already contains
-- vars: a2625f31c8826770617469656e746472657832625f32a863616765d8b50569616c6c65726769657382c8826a6d656469636174696f6e676173706972696ec8826a6d656469636174696f6e6b616d6f786963696c6c696e6463686970a264636f6465673938352d3130306c696d706c616e7465645f6279c882637665746472757468646e616d6563526578656f776e6572c882656f776e6572646d617261677370656369657363446f676876616363696e657382a365676976656e6a323032352d30362d3131646e616d656672616269657363766574c882637665746472757468a365676976656e6a323032352d30362d3131646e616d656964697374656d70657263766574c882637665746373616d697765696768745f6b67ca6432382e30
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: unique_composite_address
-- error: already contains
-- vars: a2625f31c882656f776e657263626164625f32a56761646472657373a36463697479644f736c6f646c696e656c416b65727367617461203132637a6970643031353865656d61696c707477696e406578616d706c652e6f7267646e616d65645477696e6570686f6e65683535352d3031343264746167738163766970
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: unique_edge_ends
-- error: already contains
-- vars: a4625f31c882637665746472757468625f32c8826674726561747363653131625f33c8826770617469656e7463726578625f34a2677072696d617279f46a73696e63655f796561721907ea
RELATE $_1->$_2->$_3 CONTENT $_4 RETURN AFTER;

-- rejects: check_on_edge
-- error: field `since_year`
-- vars: a4625f31c8826376657463746961625f32c8826674726561747363653130625f33c8826770617469656e74646b697769625f34a2677072696d617279f46a73696e63655f796561721907bc
RELATE $_1->$_2->$_3 CONTENT $_4 RETURN AFTER;

-- rejects: u8_range
-- error: field `years`
-- vars: a2625f31c8826376657463626164625f32a667636f6e74616374a265656d61696c706f6c6440706177732e6578616d706c656570686f6e656131676c6963656e7365685645542d39303032646e616d656a4d6574687573656c61686472617465ca6435302e30697370656369616c74796747656e6572616c65796561727319012c
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: readonly_license
-- error: field is readonly
UPDATE vet:⟨ruth⟩ SET license = 'VET-2000' RETURN AFTER;

-- rejects: link_exists_root
-- error: field `owner`
-- vars: a2625f31c8826770617469656e7463626164625f32a763616765d8b50c69616c6c65726769657380646e616d65655374726179656f776e6572c882656f776e6572666e6f626f6479677370656369657363446f676876616363696e657381a365676976656e6a323032352d30352d3032646e616d656672616269657363766574c882637665746472757468697765696768745f6b67ca6433312e35
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: link_exists_in_list_of_records
-- error: field `items.*.medication`
-- vars: a2625f31c88265766973697463626164625f32a663666565ca6438302e30656974656d7381a265646f736573016a6d656469636174696f6ec8826a6d656469636174696f6e6567686f7374676f7574636f6d6567547265617465646770617469656e74c8826770617469656e7463726578647365656ecc821a696215100063766574c882637665746472757468
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: link_exists_in_optional_record
-- error: field `chip.implanted_by`
-- vars: a2625f31c8826770617469656e7463626164625f32a863616765d8b50c69616c6c657267696573806463686970a264636f6465673030302d3030306c696d706c616e7465645f6279c882637665746567686f7374646e616d656743686970706564656f776e6572c882656f776e6572636a6f6e677370656369657363446f676876616363696e657381a365676976656e6a323032352d30352d3032646e616d656672616269657363766574c882637665746472757468697765696768745f6b67ca6433312e35
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: link_exists_in_union_arm
-- error: field `outcome`
-- vars: a2625f31c88265766973697463626164625f32a663666565ca653134302e30656974656d7380676f7574636f6d65a3646b696e6468526566657272656466726561736f6e6377686f62746fc882637665746567686f73746770617469656e74c8826770617469656e7463726578647365656ecc821a698206680063766574c882637665746373616d
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: link_exists_in_vaccines
-- error: field `vaccines.*.vet`
-- vars: a2625f31c8826770617469656e7463626164625f32a763616765d8b50c69616c6c65726769657380646e616d65664a6162626564656f776e6572c882656f776e6572636a6f6e677370656369657363446f676876616363696e657381a365676976656e6a323032352d30312d3031646e616d656672616269657363766574c882637665746567686f7374697765696768745f6b67ca6433312e35
CREATE $_1 CONTENT $_2 RETURN AFTER;

-- rejects: delete_vet_with_visits
-- error: ON DELETE REJECT
DELETE vet:⟨ruth⟩ RETURN BEFORE;

-- rejects: delete_vet_in_a_referral
-- error: is referenced by visit.outcome.to
DELETE vet:⟨tia⟩ RETURN BEFORE;

-- rejects: delete_medication_in_a_visit
-- error: is referenced by visit.items[*].medication
DELETE medication:⟨amoxicillin⟩ RETURN BEFORE;

-- write: admit_patient
-- ordered
-- roc: [{ id: 'bo', kind: 'dog', owner: 'Jon Berg' }, { id: 'kiwi', kind: 'bird', owner: 'Lena Roux' }, { id: 'luna', kind: 'cat', owner: 'Mara Ito' }, { id: 'mimi', kind: 'cat', owner: 'Noor Haddad' }, { id: 'pip', kind: 'dog', owner: 'Jon Berg' }, { id: 'rex', kind: 'dog', owner: 'Mara Ito' }, { id: 'zed', kind: 'gecko', owner: 'Noor Haddad' }]
-- vars: a2625f31c8826770617469656e7463706970625f32a763616765d8b50169616c6c65726769657380646e616d6563506970656f776e6572c882656f776e6572636a6f6e677370656369657363446f676876616363696e657380697765696768745f6b67ca63362e35
CREATE $_1 CONTENT $_2 RETURN AFTER;
SELECT record::id(id) AS id, (IF species.kind = 'Bird' THEN 'bird' ELSE IF species = 'Cat' THEN 'cat' ELSE IF species = 'Dog' THEN 'dog' ELSE species.latin END) AS kind, owner.name AS owner FROM patient ORDER BY id;

-- write: add_medication
-- ordered
-- roc: [{ id: 'amoxicillin', label: 'Amoxicillin (tablet)', stock: 200i32 }, { id: 'aspirin', label: 'Aspirin (tablet)', stock: 500i32 }, { id: 'gabapentin', label: 'Gabapentin (capsule)', stock: 40i32 }, { id: 'ivermectin', label: 'Ivermectin (injection)', stock: 15i32 }, { id: 'meloxicam', label: 'Meloxicam (liquid)', stock: 0i32 }]
-- vars: a2625f31c8826a6d656469636174696f6e696d656c6f786963616d625f32a364666f726d666c6971756964646e616d65694d656c6f786963616d6a756e69745f7072696365ca63322e35
CREATE $_1 CONTENT $_2 RETURN AFTER;
SELECT record::id(id) AS id, label AS label, stock AS stock FROM medication ORDER BY id;

-- write: restock
-- ordered
-- roc: [{ id: 'amoxicillin', label: 'Amoxicillin (tablet)', stock: 200i32 }, { id: 'aspirin', label: 'Aspirin (tablet)', stock: 500i32 }, { id: 'gabapentin', label: 'Gabapentin (capsule)', stock: 140i32 }, { id: 'ivermectin', label: 'Ivermectin (injection)', stock: 115i32 }, { id: 'meloxicam', label: 'Meloxicam (liquid)', stock: 100i32 }]
-- vars: a263616464d8b8186465666c6f6f72d8b8183c
UPDATE medication SET stock = <int>stock + <int>$add WHERE stock < $floor RETURN AFTER;
SELECT record::id(id) AS id, label AS label, stock AS stock FROM medication ORDER BY id;

-- write: certify_vet
-- ordered
-- roc: [{ id: 'ruth', specialty: 'General', years: 12u8 }, { id: 'sam', specialty: { kind: 'Surgery', board: 'ACVS' }, years: 8u8 }, { id: 'tia', specialty: { kind: 'Surgery', board: 'ECVS' }, years: 4u8 }]
UPDATE vet:⟨tia⟩ SET specialty = { kind: 'Surgery', board: 'ECVS' }, years = <int>years + 1 RETURN AFTER;
SELECT record::id(id) AS id, specialty AS specialty, years AS years FROM vet ORDER BY id;

-- write: rename_owner
-- ordered
-- roc: [{ id: 'jon', name: 'Jon B. Berg', phone: 'none', zip: '0155' }, { id: 'lena', name: 'Lena Roux', phone: '555-0188', zip: 'none' }, { id: 'mara', name: 'Mara Ito', phone: '555-0142', zip: '0158' }, { id: 'noor', name: 'Noor Haddad', phone: 'none', zip: 'none' }]
UPDATE owner:⟨jon⟩ SET name = 'Jon B. Berg' RETURN AFTER;
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone, address.zip ?? 'none' AS zip FROM owner ORDER BY id;

-- write: move_owner
-- ordered
-- roc: [{ id: 'jon', name: 'Jon B. Berg', phone: 'none', zip: '0155' }, { id: 'lena', name: 'Lena Roux', phone: 'none', zip: '69002' }, { id: 'mara', name: 'Mara Ito', phone: '555-0142', zip: '0158' }, { id: 'noor', name: 'Noor Haddad', phone: 'none', zip: 'none' }]
UPDATE owner:⟨lena⟩ SET address.zip = '69002', phone = NONE RETURN AFTER;
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone, address.zip ?? 'none' AS zip FROM owner ORDER BY id;

-- write: delete_medication_unsets_allergies
-- ordered
-- roc: [{ allergies: [], id: 'bo' }, { allergies: [], id: 'kiwi' }, { allergies: [], id: 'luna' }, { allergies: [], id: 'mimi' }, { allergies: [], id: 'pip' }, { allergies: ['Amoxicillin'], id: 'rex' }, { allergies: [], id: 'zed' }]
DELETE medication:⟨aspirin⟩ RETURN BEFORE;
SELECT allergies.map(|$v1| $v1.name) AS allergies, record::id(id) AS id FROM patient ORDER BY id;

-- write: relate_vet
-- ordered
-- roc: [{ id: 'e1', patient: 'Rex', vet: 'Ruth Okafor' }, { id: 'e2', patient: 'Rex', vet: 'Sam Petrov' }, { id: 'e3', patient: 'Bo', vet: 'Ruth Okafor' }, { id: 'e4', patient: 'Luna', vet: 'Sam Petrov' }, { id: 'e5', patient: 'Luna', vet: 'Tia Brandt' }, { id: 'e6', patient: 'Kiwi', vet: 'Ruth Okafor' }, { id: 'e7', patient: 'Mimi', vet: 'Sam Petrov' }, { id: 'e8', patient: 'Zed', vet: 'Ruth Okafor' }, { id: 'e9', patient: 'Rex', vet: 'Tia Brandt' }]
-- vars: a4625f31c8826376657463746961625f32c88266747265617473626539625f33c8826770617469656e7463726578625f34a2677072696d617279f46a73696e63655f796561721907ea
RELATE $_1->$_2->$_3 CONTENT $_4 RETURN AFTER;
SELECT record::id(id) AS id, out.name AS patient, in.name AS vet FROM treats ORDER BY id;

-- write: delete_owner_cascades_to_patients
-- ordered
-- roc: [{ id: 'bo' }, { id: 'kiwi' }, { id: 'luna' }, { id: 'pip' }, { id: 'rex' }]
DELETE owner:⟨noor⟩ RETURN BEFORE;
SELECT record::id(id) AS id FROM patient ORDER BY id;

-- query: visits_left_by_the_cascade
-- ordered
-- roc: [{ id: 'v1' }, { id: 'v2' }, { id: 'v3' }, { id: 'v4' }, { id: 'v6' }]
SELECT record::id(id) AS id FROM visit ORDER BY id;

-- query: edges_left_by_the_cascade
-- ordered
-- roc: [{ id: 'e1', patient: 'Rex', vet: 'Ruth Okafor' }, { id: 'e2', patient: 'Rex', vet: 'Sam Petrov' }, { id: 'e3', patient: 'Bo', vet: 'Ruth Okafor' }, { id: 'e4', patient: 'Luna', vet: 'Sam Petrov' }, { id: 'e5', patient: 'Luna', vet: 'Tia Brandt' }, { id: 'e6', patient: 'Kiwi', vet: 'Ruth Okafor' }, { id: 'e9', patient: 'Rex', vet: 'Tia Brandt' }]
SELECT record::id(id) AS id, out.name AS patient, in.name AS vet FROM treats ORDER BY id;

-- write: retention
-- ordered
-- roc: [{ id: 'v3' }, { id: 'v4' }, { id: 'v6' }]
-- vars: a1666265666f7265cc821a69910c8000
DELETE visit WHERE seen < $before RETURN BEFORE;
SELECT record::id(id) AS id FROM visit ORDER BY id;

-- write: add_notes
-- roc: [{ text: 'Rex is due a booster', vet: 'Ruth Okafor' }, { text: 'Order gauze', vet: 'Sam Petrov' }]
-- vars: a1625f3182a264746578747452657820697320647565206120626f6f7374657263766574c882637665746472757468a264746578746b4f72646572206761757a6563766574c882637665746373616d
BEGIN;
INSERT INTO note $_1 RETURN AFTER;
COMMIT;
SELECT text AS text, vet.name AS vet FROM note;

-- query: visit_totals
-- roc: [{ avg_fee: 66.66666666666667f, revenue: 200.0dec, visits: 3u64 }]
SELECT math::mean(<float>fee) AS avg_fee, math::sum(fee) AS revenue, count() AS visits FROM visit GROUP ALL;

-- query: no_visit_totals
-- roc: [{ visits: 0u64 }]
SELECT count() AS visits FROM visit WHERE fee > 1000.0dec GROUP ALL;
