using System;
using GTA;
using GTA.Native;

namespace Hoops.UI
{
    /// <summary>
    /// The game's own top-left prompt, the one that tells you which button to press -- used
    /// rather than drawn text so the button pictures are right on pad and keyboard both: the
    /// game puts in whatever ~INPUT_...~ is on the thing the player is holding.
    ///
    /// It has to be issued again EVERY FRAME to stay up, so a request is latched and Tick puts
    /// it up once a frame until the asking stops. The court asks every frame it wants it, so the
    /// latch is short: a prompt should not hang about after the ball goes down.
    /// </summary>
    internal static class Help
    {
        private static string _wanted;
        private static int _askedAt;

        private const int HoldMs = 150;

        /// <summary>ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME stops at 99 bytes, so longer prompts go in pieces.</summary>
        private const int ChunkSize = 96;

        public static void Show(string message)
        {
            if (string.IsNullOrEmpty(message)) return;

            _wanted = message;
            _askedAt = Game.GameTime;
        }

        /// <summary>Once a frame, from Main.</summary>
        public static void Tick()
        {
            if (string.IsNullOrEmpty(_wanted)) return;

            if (Game.GameTime - _askedAt > HoldMs)
            {
                _wanted = null;
                return;
            }

            try
            {
                Function.Call(Hash.BEGIN_TEXT_COMMAND_DISPLAY_HELP, _wanted.Length > ChunkSize ? "CELL_EMAIL_BCON" : "STRING");

                for (var i = 0; i < _wanted.Length; i += ChunkSize)
                {
                    Function.Call(Hash.ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME,
                                  _wanted.Substring(i, Math.Min(ChunkSize, _wanted.Length - i)));
                }

                Function.Call(Hash.END_TEXT_COMMAND_DISPLAY_HELP, 0, false, false, -1);
            }
            catch (Exception ex)
            {
                Core.Log.Debug("Help prompt failed: " + ex.Message);
            }
        }
    }

    /// <summary>
    /// A line on the feed, through the three natives the game's own scripts use -- not the
    /// wrapper, whose name changed between ScriptHookVDotNet builds and broke Posted Up on every
    /// older one.
    /// </summary>
    internal static class Feed
    {
        public static void Ticker(string message)
        {
            if (string.IsNullOrEmpty(message)) return;

            try
            {
                Function.Call(Hash.BEGIN_TEXT_COMMAND_THEFEED_POST, "STRING");
                Function.Call(Hash.ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME, message);
                Function.Call(Hash.END_TEXT_COMMAND_THEFEED_POST_TICKER, false, true);
            }
            catch (Exception ex)
            {
                Core.Log.Debug("Feed post failed: " + ex.Message);
            }
        }

        /// <summary>Something went wrong, said to the player rather than the log.</summary>
        public static void Problem(string message)
        {
            Ticker("~o~" + Core.Build.Name + ":~s~ " + message);
        }
    }
}
