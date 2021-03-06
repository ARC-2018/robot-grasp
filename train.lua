require 'torch'
require 'cutorch'
require 'nn'
require 'cunn'
require 'optim'
require 'paths'

local BATCH_SIZE = tonumber(arg[2]) or 200
local CROP_SIZE = 128
local MAX_STEP = tonumber(arg[3]) or 800

function accuracy (prediction, target)
  local _, yHat = torch.max(prediction, 2)
  return yHat:eq(target):mean()
end

print('# of CUDA devices:', cutorch.getDeviceCount())
print('using device:', cutorch.getDevice())
print('saving checkpoint models to:', arg[1])
paths.mkdir(arg[1])

torch.manualSeed(3)

local model = require './model'
print(model)
model:cuda()
model:training()
local loss = nn.CrossEntropyCriterion()
loss:cuda()

local train = torch.load('train.t7')
local val = torch.load('val.t7')

local n = train['y']:size(1)
print('# of samples', n)

local mParams, mGrad = model:getParameters()
local cost
function _fgrad (rgb, d, y)
  function fgrad (params)
    mParams:copy(params)
    model:zeroGradParameters()
    local yHat = model:forward({rgb, d})
    cost = loss:forward(yHat, y)
    local dl = loss:backward(yHat, y)
    model:backward({rgb, d}, dl)
    return cost, mGrad
  end
  return fgrad
end

local rgb, d, y
local state = {}
for step = 1, MAX_STEP do
  -- construct mini-batch
  local i = step * BATCH_SIZE % n
  if i < BATCH_SIZE then
    i = 1
  end
  local j = math.min(i + BATCH_SIZE - 1, n)
  rgb = train['x'][1][{{i, j}}]:cuda()
  d = train['x'][2][{{i, j}}]:cuda()
  -- rgb only
  -- d:zero()
  -- depth only
  rgb:zero()
  y = train['y'][{{i, j}}]:cuda()

  optim.adam(_fgrad(rgb, d, y), mParams, state)
  print(step, cost, mGrad:norm())

  -- checkpoint the model
  if step % 200 == 0 then
    model:clearState()
    torch.save(arg[1]..'/model.'..step..'.t7', model)
  end
end

-- evaluate on val
model:evaluate()

rgb = val['x'][1][{{1,1000}}]:cuda()
d = val['x'][2][{{1,1000}}]:cuda()
y = val['y'][{{1,1000}}]:cuda()
local yHat = model:forward({rgb, d})

local valCost = loss:forward(yHat, y)
print('val entropy:', valCost)
print('val acc:', accuracy(yHat, y))

model:clearState()
torch.save(arg[1]..'/model.'..MAX_STEP..'.t7', model)
