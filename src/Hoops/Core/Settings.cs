using System;

namespace Hoops.Core
{
    /// <summary>
    /// Hoops.ini, and little in it on purpose: the court is where it is and plays how it plays,
    /// and a player has nothing to set but whether it is on.
    /// </summary>
    internal sealed class Settings
    {
        public bool Enabled = true;

        public LogLevel LogLevel = LogLevel.Info;

        /// <summary>
        /// POSTED UP HAS THIS SAME COURT BUILT IN. With both installed, two games would offer
        /// themselves on one court -- two rings on the floor, two balls, two scores -- and nothing
        /// on screen would say why. So Hoops stands down when Posted Up is there, and says so in
        /// its log. False runs both anyway.
        /// </summary>
        public bool StandDownForPostedUp = true;

        public static Settings Load()
        {
            var s = new Settings();

            try
            {
                var ini = IniFile.Load(Paths.Ini);

                s.Enabled = ini.GetBool("General", "Enabled", s.Enabled);
                s.StandDownForPostedUp = ini.GetBool("General", "StandDownForPostedUp", s.StandDownForPostedUp);

                LogLevel level;
                if (Enum.TryParse(ini.GetString("General", "LogLevel", s.LogLevel.ToString()), true, out level)) s.LogLevel = level;
            }
            catch (Exception ex)
            {
                Log.Error("Hoops.ini could not be read; the defaults are in use.", ex);
            }

            return s;
        }
    }

    /// <summary>
    /// Which other script has a menu up right now, or null. The set's convention: a script with a
    /// menu open parks its own name in the AppDomain's "MenuOpen" slot while it is up, and one
    /// with something to offer looks there first. Every SHVDN script shares the one AppDomain.
    /// </summary>
    internal static class Menus
    {
        public static string Owner()
        {
            try { return AppDomain.CurrentDomain.GetData("MenuOpen") as string; }
            catch { return null; }
        }
    }
}
