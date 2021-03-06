import unittest
import pexpect
import os
import sin_testing as st

class TestXref(st.SmokeTest):

    @st.sinan("xref")
    def do_xref(self, child):
       child.expect("Looking for Calls to Deprecated Functions")
       child.expect(pexpect.EOF)

    def test_xref(self):
        app_desc = st.AppDesc(user_name = "Smoke Test User",
                              email = "noreply@erlware.org",
                              copyright_holder = "Smoke Test Copy, LLC.",
                              project_name = "smprj",
                              project_version = "0.21.0.0",
                              app_names = ["app1", "app2", "app3"])


        self.do_run(app_desc)
        currentdir = os.getcwd()
        projdir = os.path.join(currentdir, app_desc.project_name)
        builddir = os.path.join(projdir, "_build", "development")
        os.chdir(projdir)
        self.do_xref()



if __name__ == '__main__':
    unittest.main()
