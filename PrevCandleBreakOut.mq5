//+------------------------------------------------------------------+
//|                                          PrevCandleBreakOut.mq5  |
//|                                    Previous Candle Breakout EA   |
//+------------------------------------------------------------------+
#property copyright "PrevCandleBreakOut"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- Input Parameters
input ENUM_TIMEFRAMES Timeframe       = PERIOD_H1;  // Timeframe
input double          RiskPercent     = 1.0;        // Risk % of Balance
input int             SlPoints        = 50;         // Stop Loss in Points
input int             TpPoints        = 50;         // Take Profit in Points
input int             TslTriggerPoints = 20;        // Trailing Stop Trigger Points
input int             TslPoints       = 10;         // Trailing Stop Points
input int             MagicNumber     = 123456;     // Magic Number

//--- Global Objects
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
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

   //--- Trailing Stop Management
   ManageTrailingStop(bid, ask);

   //--- Check for new candle and entry signals
   CheckEntrySignals();
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

   //--- Check if already have position
   if(HasOpenPosition()) return;

   //--- BUY Signal: Close breaks above previous high
   if(rates[0].close > rates[1].high)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = entry - SlPoints * _Point;
      double tp = entry + TpPoints * _Point;

      double lots = CalcLots(entry - sl);

      trade.Buy(lots, _Symbol, entry, sl, tp);
   }
   //--- SELL Signal: Close breaks below previous low
   else if(rates[0].close < rates[1].low)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = entry + SlPoints * _Point;
      double tp = entry - TpPoints * _Point;

      double lots = CalcLots(sl - entry);

      trade.Sell(lots, _Symbol, entry, sl, tp);
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
