with Sitefetch.Messages;
with Terminal_Styles;

package body Sitefetch.Progress_Format is
   function Format
     (Event : Progress_Event;
      URL   : String) return String
   is
   begin
      case Event is
         when Progress_Fetching =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.fetch", "url", URL),
               Terminal_Styles.Role_Info);
         when Progress_Written =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.write", "url", URL),
               Terminal_Styles.Role_Success);
         when Progress_Skipped_External =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.external", "url", URL),
               Terminal_Styles.Role_Warning);
         when Progress_Skipped_Unsupported =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.ignore", "url", URL),
               Terminal_Styles.Role_Muted);
         when Progress_Warning_Dangerous =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.danger", "url", URL),
               Terminal_Styles.Role_Warning);
         when Progress_Skipped_Dangerous =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.skip_danger", "url", URL),
               Terminal_Styles.Role_Warning);
         when Progress_Already_Visited =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.visited", "url", URL),
               Terminal_Styles.Role_Muted);
         when Progress_Skipped_Limit =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.ignore", "url", URL),
               Terminal_Styles.Role_Warning);
         when Progress_Cache_Revalidate =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.cache_revalidate", "url", URL),
               Terminal_Styles.Role_Muted);
         when Progress_Cache_Reused =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.cache_reused", "url", URL),
               Terminal_Styles.Role_Muted);
         when Progress_Cache_Rejected =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.cache_rejected", "url", URL),
               Terminal_Styles.Role_Muted);
         when Progress_Resume_Attempt =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.resume", "url", URL),
               Terminal_Styles.Role_Muted);
         when Progress_Retry =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.retry", "url", URL),
               Terminal_Styles.Role_Warning);
         when Progress_Robots_Allowed =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.robots_allow", "url", URL),
               Terminal_Styles.Role_Muted);
         when Progress_Robots_Disallowed =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.robots_disallow", "url", URL),
               Terminal_Styles.Role_Warning);
         when Progress_Robots_Loaded =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.robots_loaded", "url", URL),
               Terminal_Styles.Role_Muted);
         when Progress_Robots_Failed =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.robots_failed", "url", URL),
               Terminal_Styles.Role_Warning);
         when Progress_Failed =>
            return Terminal_Styles.Line
              (Sitefetch.Messages.Text ("progress.fail", "url", URL),
               Terminal_Styles.Role_Error);
         when Progress_Redirected =>
            return Terminal_Styles.Line
              ("[>] " & URL,
               Terminal_Styles.Role_Info);
      end case;
   end Format;
end Sitefetch.Progress_Format;
