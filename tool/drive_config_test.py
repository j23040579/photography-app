import json
import unittest
from write_drive_defines import build_settings


class DriveBuildSettingsTest(unittest.TestCase):
    def settings(self, **changes):
        return {"DRIVE_CLIENT_ID": "12345-example.apps.googleusercontent.com",
                "DRIVE_CLIENT_SECRET": "example-secret", **changes}

    def test_trims_pasted_edge_whitespace(self):
        settings = build_settings(self.settings(DRIVE_CLIENT_ID=" 12345-example.apps.googleusercontent.com\n"))
        self.assertEqual(settings["DRIVE_CLIENT_ID"], "12345-example.apps.googleusercontent.com")

    def test_rejects_json_project_id_and_assignment_without_echoing_input(self):
        for value in ('{"client_id":"private-value"}', 'my-project-id',
                      'DRIVE_CLIENT_ID=12345-example.apps.googleusercontent.com',
                      '"12345-example.apps.googleusercontent.com"'):
            with self.subTest(value=value):
                with self.assertRaises(ValueError) as error:
                    build_settings(self.settings(DRIVE_CLIENT_ID=value))
                self.assertNotIn(value, str(error.exception))

    def test_requires_both_configuration_fields(self):
        with self.assertRaises(ValueError):
            build_settings(self.settings(DRIVE_CLIENT_SECRET="  "))

    def test_accepts_quoted_secret_values(self):
        for value in ('"example-secret"', "'example-secret'"):
            settings = build_settings(self.settings(DRIVE_CLIENT_SECRET=value))
            self.assertEqual(settings['DRIVE_CLIENT_SECRET'], 'example-secret')

    def test_accepts_a_copied_json_field(self):
        settings = build_settings(self.settings(DRIVE_CLIENT_SECRET='"DRIVE_CLIENT_SECRET": "example-secret",'))
        self.assertEqual(settings['DRIVE_CLIENT_SECRET'], 'example-secret')

    def test_accepts_supported_json_documents(self):
        for document in ({'client_secret':'example-secret'}, {'DRIVE_CLIENT_SECRET':'example-secret'},
                         {'installed':{'client_id':self.settings()['DRIVE_CLIENT_ID'], 'client_secret':'example-secret'}}):
            settings = build_settings(self.settings(DRIVE_CLIENT_SECRET=json.dumps(document)))
            self.assertEqual(settings['DRIVE_CLIENT_SECRET'], 'example-secret')

    def test_rejects_mismatched_clients_without_echoing_the_document(self):
        document = json.dumps({'installed':{'client_id':'another-client', 'client_secret':'private-secret'}})
        with self.assertRaises(ValueError) as error:
            build_settings(self.settings(DRIVE_CLIENT_SECRET=document))
        self.assertNotIn('private-secret', str(error.exception))
        self.assertNotIn('another-client', str(error.exception))

    def test_rejects_missing_or_ambiguous_secret_fields(self):
        for value in ('{}', '{"client_secret":42}', '{"unrelated":"private"}',
                      '{"installed":{},"web":{}}', '"unfinished'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                build_settings(self.settings(DRIVE_CLIENT_SECRET=value))


if __name__ == "__main__":
    unittest.main()
