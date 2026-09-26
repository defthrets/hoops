using System;
using System.IO;
using GTA;
using Hoops.Core;
using Hoops.Court;

namespace Hoops
{
    /// <summary>
    /// HOOPS: shooting hoops on the Chamberlain Hills basketball court.
    ///
    /// Walk into the ring on the court and press the button to pick up the ball. Hold to shoot:
    /// the meter runs up and down, the line out of his hand rises and stretches with it, and it
    /// fades before it comes down -- where the ball lands is yours to judge. Down through a hoop
    /// is two, or three from past the line.
    ///
    /// THE GAME IS IN Court\, AND IT IS POSTED UP'S TOO. Posted Up has the same court built in,
    /// and tools\sync-court.py copies Court\ into it with the namespace changed and nothing else.
    /// Edit the court here, never there. This file is the only one that knows it is in Hoops:
    /// it tells the court where this mod keeps its log, its ini, its help box and its feed.
    /// </summary>
    public sealed class Main : Script
    {
        private readonly Core.Settings _cfg;
        private readonly Shootaround _court = new Shootaround();

        private bool _parked;
        private bool _standDown;
        private bool _saidTick;

        public Main()
        {
            try
            {
                // Fully qualified: Script has a Settings of its own that wins name resolution.
                _cfg = Core.Settings.Load();
                Log.Level = _cfg.LogLevel;

                // WHAT THE COURT ASKS OF THIS MOD. See Court\CourtHost.cs.
                CourtHost.Info = Log.Info;
                CourtHost.Warn = Log.Warn;
                CourtHost.Debug = Log.Debug;
                CourtHost.Read = (section, key, fallback) => IniFile.Load(Paths.Ini).GetString(section, key, fallback);
                CourtHost.Put = (section, key, value) => IniFile.SetValue(Paths.Ini, section, key, value);
                CourtHost.Help = UI.Help.Show;
                CourtHost.Ticker = UI.Feed.Ticker;
                CourtHost.Problem = UI.Feed.Problem;
                CourtHost.Busy = () => Menus.Owner() != null;
                CourtHost.Counted = UI.Ledger.Count;
                CourtHost.OnPad = () => Game.LastInputMethod == InputMethod.GamePad;

                // Posted Up beside this runs the same court. See Settings.StandDownForPostedUp.
                _standDown = _cfg.StandDownForPostedUp && File.Exists(Path.Combine(Paths.Scripts, "Hoodrich.dll"));

                if (_standDown)
                {
                    Log.Warn("Posted Up is installed here and has this same court built in, so Hoops stands down: " +
                             "two games on one court is two rings, two balls and two scores. Set " +
                             "StandDownForPostedUp=false in Hoops.ini to run both anyway.");
                }

                Interval = 0;
                Tick += OnTick;
                Aborted += OnAborted;

                Log.Info(Build.Name + " " + Build.Version + " by " + Build.By + " loaded" +
                         (_standDown ? ", standing down for Posted Up." : "."));
            }
            catch (Exception ex)
            {
                _parked = true;
                Log.Error("Failed to start; disabled for this session.", ex);
            }
        }

        private void OnTick(object sender, EventArgs e)
        {
            Core.Pace.Begin();

            // The set's mark, for a few seconds after load. See UI.Splash.
            UI.Splash.Render();

            if (_parked || _cfg == null || !_cfg.Enabled || _standDown) return;

            try
            {
                _court.Update();
                UI.Help.Tick();
            }
            catch (Exception ex)
            {
                // One bad frame is not worth the mod: said once, and the next frame goes on.
                if (!_saidTick)
                {
                    _saidTick = true;
                    Log.Error("The court's tick threw; carrying on.", ex);
                }
            }
        }

        private void OnAborted(object sender, EventArgs e)
        {
            try { _court.RestoreWorld(); }
            catch { }
        }
    }
}
