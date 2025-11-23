//+------------------------------------------------------------------+
//|                                          PrevCandleBreakOut.mq5  |
//|                                    Previous Candle Breakout EA   |
//+------------------------------------------------------------------+
#property copyright "PrevCandleBreakOut"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

//--- Enums for Time Filter
enum ENUM_HOUR {
   H_00=0,              // 00:
   H_01=1,              // 01:
   H_02=2,              // 02:
   H_03=3,              // 03:
   H_04=4,              // 04:
   H_05=5,              // 05:
   H_06=6,              // 06:
   H_07=7,              // 07:
   H_08=8,              // 08:
   H_09=9,              // 09:
   H_10=10,             // 10:
   H_11=11,             // 11:
   H_12=12,             // 12:
   H_13=13,             // 13:
   H_14=14,             // 14:
   H_15=15,             // 15:
   H_16=16,             // 16:
   H_17=17,             // 17:
   H_18=18,             // 18:
   H_19=19,             // 19:
   H_20=20,             // 20:
   H_21=21,             // 21:
   H_22=22,             // 22:
   H_23=23              // 23:
};

enum ENUM_MINUTE {
   M_00=0,              // :00
   M_05=5,              // :05
   M_10=10,             // :10
   M_15=15,             // :15
   M_20=20,             // :20
   M_25=25,             // :25
   M_30=30,             // :30
   M_35=35,             // :35
   M_40=40,             // :40
   M_45=45,             // :45
   M_50=50,             // :50
   M_55=55              // :55
};

//--- Input Parameters - Main
input group "=== Main Settings ==="
input ENUM_TIMEFRAMES Timeframe       = PERIOD_H1;  // Timeframe
input double          RiskPercent     = 1.0;        // Risk % of Balance
input int             SlPoints        = 50;         // Stop Loss in Points
input int             TpPoints        = 50;         // Take Profit in Points
input int             MagicNumber     = 123456;     // Magic Number

//--- Input Parameters - Trailing Stop
input group "=== Trailing Stop ==="
input bool            UseTrailingStop    = true;    // Use Trailing Stop
input int             TslTriggerPoints   = 20;      // Trailing Stop Trigger Points
input int             TslPoints          = 10;      // Trailing Stop Points

//--- Input Parameters - Spread Filter
input group "=== Spread Filter ==="
input bool            UseSpreadFilter    = true;    // Use Spread Filter
input int             MaxSpreadPoints    = 20;      // Max Spread in Points

//--- Input Parameters - Time Filter
input group "=== Time Filter ==="
input bool            UseTimeFilter      = true;    // Use Time Filter
input ENUM_HOUR       StartHour          = H_08;    // Start Hour
input ENUM_MINUTE     StartMinute        = M_00;    // Start Minute
input ENUM_HOUR       EndHour            = H_20;    // End Hour
input ENUM_MINUTE     EndMinute          = M_00;    // End Minute

//--- Input Parameters - Max Daily Trades
input group "=== Max Daily Trades ==="
input bool            UseMaxDailyTrades  = true;    // Use Max Daily Trades
input int             MaxDailyTrades     = 3;       // Max Trades Per Day

//--- Input Parameters - Break Even
input group "=== Break Even ==="
input bool            UseBreakEven       = true;    // Use Break Even
input int             BreakEvenTrigger   = 30;      // Break Even Trigger Points
input int             BreakEvenProfit    = 5;       // Break Even Profit Points

//--- Input Parameters - Partial Close
input group "=== Partial Close ==="
input bool            UsePartialClose    = true;    // Use Partial Close
input int             PartialCloseTrigger = 40;     // Partial Close Trigger Points
input double          PartialClosePercent = 50.0;   // Partial Close Percent (%)

//--- Global Objects
CTrade trade;

//--- Global Variables
datetime lastTradeDate = 0;
int      dailyTradeCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   //--- Reset daily counter
   ResetDailyCounter();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- Reset daily counter on new day
   ResetDailyCounter();

   //--- Position Management
   if(UseBreakEven) ManageBreakEven(bid, ask);
   if(UsePartialClose) ManagePartialClose(bid, ask);
   if(UseTrailingStop) ManageTrailingStop(bid, ask);

   //--- Check for new candle and entry signals
   CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| Reset daily trade counter on new day                              |
//+------------------------------------------------------------------+
void ResetDailyCounter()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(today != lastTradeDate)
   {
      lastTradeDate = today;
      dailyTradeCount = 0;
   }
}

//+------------------------------------------------------------------+
//| Check Spread Filter                                                |
//+------------------------------------------------------------------+
bool IsSpreadOK()
{
   if(!UseSpreadFilter) return true;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= MaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Check Time Filter                                                  |
//+------------------------------------------------------------------+
bool IsTimeOK()
{
   if(!UseTimeFilter) return true;

   MqlDateTime dt;
   TimeCurrent(dt);

   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes = (int)StartHour * 60 + (int)StartMinute;
   int endMinutes = (int)EndHour * 60 + (int)EndMinute;

   //--- Handle overnight sessions (e.g., 22:00 - 06:00)
   if(startMinutes > endMinutes)
   {
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
   }

   return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
}

//+------------------------------------------------------------------+
//| Check Max Daily Trades                                             |
//+------------------------------------------------------------------+
bool CanTradeToday()
{
   if(!UseMaxDailyTrades) return true;

   return (dailyTradeCount < MaxDailyTrades);
}

//+------------------------------------------------------------------+
//| Manage Break Even for all positions                               |
//+------------------------------------------------------------------+
void ManageBreakEven(double bid, double ask)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      CPositionInfo pos;
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != MagicNumber) continue;

      double openPrice = pos.PriceOpen();
      double currentSL = pos.StopLoss();
      double beLevel = NormalizeDouble(openPrice + BreakEvenProfit * _Point, _Digits);
      double beLevelSell = NormalizeDouble(openPrice - BreakEvenProfit * _Point, _Digits);

      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         //--- Check if BE not yet applied and trigger reached
         if(currentSL < openPrice && bid >= openPrice + BreakEvenTrigger * _Point)
         {
            if(trade.PositionModify(pos.Ticket(), beLevel, pos.TakeProfit()))
            {
               Print("Pos #", pos.Ticket(), " moved to Break Even");
            }
         }
      }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
      {
         //--- Check if BE not yet applied and trigger reached
         if(currentSL > openPrice || currentSL == 0)
         {
            if(ask <= openPrice - BreakEvenTrigger * _Point)
            {
               if(trade.PositionModify(pos.Ticket(), beLevelSell, pos.TakeProfit()))
               {
                  Print("Pos #", pos.Ticket(), " moved to Break Even");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Partial Close for all positions                            |
//+------------------------------------------------------------------+
void ManagePartialClose(double bid, double ask)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      CPositionInfo pos;
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != MagicNumber) continue;

      double openPrice = pos.PriceOpen();
      double volume = pos.Volume();
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      //--- Calculate close volume
      double closeVolume = NormalizeDouble(volume * PartialClosePercent / 100.0, 2);
      closeVolume = MathFloor(closeVolume / lotStep) * lotStep;

      //--- Check if partial close is possible
      if(closeVolume < minLot || (volume - closeVolume) < minLot) continue;

      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         if(bid >= openPrice + PartialCloseTrigger * _Point)
         {
            //--- Check if position hasn't been partially closed yet (volume check)
            if(trade.PositionClosePartial(pos.Ticket(), closeVolume))
            {
               Print("Pos #", pos.Ticket(), " partially closed: ", closeVolume, " lots");
            }
         }
      }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
      {
         if(ask <= openPrice - PartialCloseTrigger * _Point)
         {
            if(trade.PositionClosePartial(pos.Ticket(), closeVolume))
            {
               Print("Pos #", pos.Ticket(), " partially closed: ", closeVolume, " lots");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop for all positions                            |
//+------------------------------------------------------------------+
void ManageTrailingStop(double bid, double ask)
{
   if(TslTriggerPoints <= 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      CPositionInfo pos;
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != MagicNumber) continue;

      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         if(bid > pos.PriceOpen() + TslTriggerPoints * _Point)
         {
            double sl = NormalizeDouble(bid - TslPoints * _Point, _Digits);

            if(sl > pos.StopLoss())
            {
               if(trade.PositionModify(pos.Ticket(), sl, pos.TakeProfit()))
               {
                  Print("Pos #", pos.Ticket(), " was modified by tsl...");
               }
            }
         }
      }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
      {
         if(ask < pos.PriceOpen() - TslTriggerPoints * _Point)
         {
            double sl = NormalizeDouble(ask + TslPoints * _Point, _Digits);

            if(sl < pos.StopLoss() || pos.StopLoss() == 0)
            {
               if(trade.PositionModify(pos.Ticket(), sl, pos.TakeProfit()))
               {
                  Print("Pos #", pos.Ticket(), " was modified by tsl...");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for entry signals on new candle                             |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   MqlRates rates[];
   if(CopyRates(_Symbol, Timeframe, 1, 2, rates) != 2) return;
   ArraySetAsSeries(rates, true);

   static datetime timestamp;
   if(timestamp == rates[0].time) return;
   timestamp = rates[0].time;

   //--- Check filters
   if(!IsSpreadOK())
   {
      Print("Trade skipped: Spread too high");
      return;
   }

   if(!IsTimeOK())
   {
      return; // Silent skip for time filter
   }

   if(!CanTradeToday())
   {
      Print("Trade skipped: Max daily trades reached");
      return;
   }

   //--- Check if already have position
   if(HasOpenPosition()) return;

   //--- BUY Signal: Close breaks above previous high
   if(rates[0].close > rates[1].high)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = entry - SlPoints * _Point;
      double tp = entry + TpPoints * _Point;

      double lots = CalcLots(entry - sl);

      if(trade.Buy(lots, _Symbol, entry, sl, tp))
      {
         dailyTradeCount++;
         Print("BUY opened. Daily trades: ", dailyTradeCount);
      }
   }
   //--- SELL Signal: Close breaks below previous low
   else if(rates[0].close < rates[1].low)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = entry + SlPoints * _Point;
      double tp = entry - TpPoints * _Point;

      double lots = CalcLots(sl - entry);

      if(trade.Sell(lots, _Symbol, entry, sl, tp))
      {
         dailyTradeCount++;
         Print("SELL opened. Daily trades: ", dailyTradeCount);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if we already have an open position                         |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      CPositionInfo pos;
      if(pos.SelectByIndex(i))
      {
         if(pos.Symbol() == _Symbol && pos.Magic() == MagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                       |
//+------------------------------------------------------------------+
double CalcLots(double slPoints)
{
   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   //--- Calculate risk amount from balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   int ticks = (int)(NormalizeDouble(slPoints, _Digits) / ticksize);
   double risk = ticks * tickvalue;

   if(risk == 0) return minlot;

   double lots = riskMoney / risk;
   lots = (int)(lots / lotstep) * lotstep;

   //--- Clamp to min/max lot
   if(lots < minlot) lots = minlot;
   if(lots > maxlot) lots = maxlot;

   return lots;
}
//+------------------------------------------------------------------+
