package Sitefetch.Messages is
   --  Set the active locale used for subsequent message rendering.
   --
   --  @param Locale_Name Locale identifier, such as en, de, or de-AT.
   procedure Set_Locale (Locale_Name : String);

   --  Detect the active locale from the process environment.
   --
   --  Locale detection checks LC_ALL, LC_MESSAGES, and LANG, in that order.
   --  Empty, C, and POSIX values select English.
   procedure Detect_System_Locale;

   --  Return the active locale used for message rendering.
   --
   --  @return Active normalized locale identifier.
   function Current_Locale return String;

   --  Return the localized text for Key.
   --
   --  @param Key Message catalog key.
   --  @return Localized message text, or Key when lookup fails.
   function Text (Key : String) return String;

   --  Return localized text with one replacement argument.
   --
   --  @param Key Message catalog key.
   --  @param Arg_Key Replacement argument key.
   --  @param Arg_Value Replacement argument value.
   --  @return Localized rendered message text, or Key when lookup fails.
   function Text
     (Key       : String;
      Arg_Key   : String;
      Arg_Value : String) return String;

   --  Return localized text with two replacement arguments.
   --
   --  @param Key Message catalog key.
   --  @param Arg_1_Key First replacement argument key.
   --  @param Arg_1_Value First replacement argument value.
   --  @param Arg_2_Key Second replacement argument key.
   --  @param Arg_2_Value Second replacement argument value.
   --  @return Localized rendered message text, or Key when lookup fails.
   function Text
     (Key         : String;
      Arg_1_Key   : String;
      Arg_1_Value : String;
      Arg_2_Key   : String;
      Arg_2_Value : String) return String;
end Sitefetch.Messages;
