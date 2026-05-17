#ifndef AVG_BUCKET_H
#define AVG_BUCKET_H

struct AvgBucket {
  double bpmSum = 0;
  double spo2Sum = 0;
  double tempSum = 0;
  double irSum = 0;
  double varSum = 0;
  double activitySum = 0;
  int count = 0;
};

#endif

