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

    def test_rejects_a_secret_pasted_as_an_entire_document(self):
        with self.assertRaises(ValueError):
            build_settings(self.settings(DRIVE_CLIENT_SECRET='{"client_secret":"value"}'))


if __name__ == "__main__":
    unittest.main()
