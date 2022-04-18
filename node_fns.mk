#
# Copyright (C) 2007 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Clears a list of variables using ":=".
#
# E.g.,
#   $(call clear-var-list,A B C)
# would be the same as:
#   A :=
#   B :=
#   C :=
#
# $(1): list of variable names to clear
#
define clear-var-list
$(foreach v,$(1),$(eval $(v):=))
endef

#
# Copies a list of variables into another list of variables.
# The target list is the same as the source list, but has
# a dotted prefix affixed to it.
#
# E.g.,
#   $(call copy-var-list, PREFIX, A B)
# would be the same as:
#   PREFIX.A := $(A)
#   PREFIX.B := $(B)
#
# $(1): destination prefix
# $(2): list of variable names to copy
#
define copy-var-list
$(foreach v,$(2),$(eval $(strip $(1)).$(v):=$($(v))))
endef

#
# Moves a list of variables into another list of variables.
# The variable names differ by a prefix.  After moving, the
# source variable is cleared.
#
# NOTE: Spaces are not allowed around the prefixes.
#
# E.g.,
#   $(call move-var-list,SRC,DST,A B)
# would be the same as:
#   DST.A := $(SRC.A)
#   SRC.A :=
#   DST.B := $(SRC.B)
#   SRC.B :=
#
# $(1): source prefix
# $(2): destination prefix
# $(3): list of variable names to move
#
define move-var-list
$(foreach v,$(3), \
  $(eval $(2).$(v) := $($(1).$(v))) \
  $(eval $(1).$(v) :=) \
 )
endef

#
# $(1): haystack
# $(2): needle
#
# Guarantees that needle appears at most once in haystack,
# without changing the order of other elements in haystack.
# If needle appears multiple times, only the first occurrance
# will survive.
#
# How it works:
#
# - Stick everything in haystack into a single word,
#   with "|||" separating the words.
# - Replace occurrances of "|||$(needle)|||" with "||| |||",
#   breaking haystack back into multiple words, with spaces
#   where needle appeared.
# - Add needle between the first and second words of haystack.
# - Replace "|||" with spaces, breaking haystack back into
#   individual words.
#
define uniq-word
$(strip \
  $(if $(filter-out 0 1,$(words $(filter $(2),$(1)))), \
    $(eval h := |||$(subst $(space),|||,$(strip $(1)))|||) \
    $(eval h := $(subst |||$(strip $(2))|||,|||$(space)|||,$(h))) \
    $(eval h := $(word 1,$(h)) $(2) $(wordlist 2,9999,$(h))) \
    $(subst |||,$(space),$(h)) \
   , \
    $(1) \
 ))
endef

INHERIT_TAG := @inherit:

#
# Walks through the list of variables, each qualified by the prefix,
# and finds instances of words beginning with INHERIT_TAG.  Scrape
# off INHERIT_TAG from each matching word, and return the sorted,
# unique set of those words.
#
# E.g., given
#   PREFIX.A := A $(INHERIT_TAG)aaa B C
#   PREFIX.B := B $(INHERIT_TAG)aaa C $(INHERIT_TAG)bbb D E
# Then
#   $(call get-inherited-nodes,PREFIX,A B)
# returns
#   aaa bbb
#
# $(1): variable prefix
# $(2): list of variables to check
#
define get-inherited-nodes
$(sort \
  $(subst $(INHERIT_TAG),, \
    $(filter $(INHERIT_TAG)%, \
      $(foreach v,$(2),$($(1).$(v))) \
 )))
endef

#
# for each variable ( (prefix + name) * vars ):
#   get list of inherited words; if not empty:
#     for each inherit:
#       replace the first occurrence with (prefix + inherited + var)
#       clear the source var so we can't inherit the value twice
#
# $(1): context prefix
# $(2): name of this node
# $(3): list of variable names
#
define _expand-inherited-values
  $(foreach v,$(3), \
    $(eval ### "Shorthand for the name of the target variable") \
    $(eval _eiv_tv := $(1).$(2).$(v)) \
    $(eval ### "Get the list of nodes that this variable inherits") \
    $(eval _eiv_i := \
        $(sort \
            $(patsubst $(INHERIT_TAG)%,%, \
                $(filter $(INHERIT_TAG)%, $($(_eiv_tv)) \
     )))) \
    $(foreach i,$(_eiv_i), \
      $(eval ### "Make sure that this inherit appears only once") \
      $(eval $(_eiv_tv) := \
          $(call uniq-word,$($(_eiv_tv)),$(INHERIT_TAG)$(i))) \
      $(eval ### "Expand the inherit tag") \
      $(eval $(_eiv_tv) := \
          $(strip \
              $(patsubst $(INHERIT_TAG)$(i),$($(1).$(i).$(v)), \
                  $($(_eiv_tv))))) \
      $(eval ### "Clear the child so DAGs don't create duplicate entries" ) \
      $(eval $(1).$(i).$(v) :=) \
      $(eval ### "If we just inherited ourselves, it's a cycle.") \
      $(if $(filter $(INHERIT_TAG)$(2),$($(_eiv_tv))), \
        $(warning Cycle detected between "$(2)" and "$(i)" for context "$(1)") \
        $(error import of "$(2)" failed) \
      ) \
     ) \
   ) \
   $(eval _eiv_tv :=) \
   $(eval _eiv_i :=)
endef

#
# $(1): context prefix  #内容前缀：如 _nic.PRODUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]]
# $(2): makefile representing this node   # 下同， 如device/friendly-arm/tiny4412/full_tiny4412.mk,但是这儿只有一个mk文件，不是list列表
# $(3): list of node variable names  # 下同
#
# _include_stack contains the list of included files, with the most recent files first. #_include_stack 包含included文件的列表，最近的文件在前。
define _import-node
  $(eval _include_stack := $(2) $$(_include_stack))  #添加mk文件到开头
  $(call clear-var-list, $(3))       #使用前， 清除变量列表$(3)
  $(eval LOCAL_PATH := $(patsubst %/,%,$(dir $(2))))  #获取device/friendly-arm/tiny4412/full_tiny4412.mk的目录为device/friendly-arm/tiny4412
  $(eval MAKEFILE_LIST :=)  # 使用前，清空变量MAKEFILE_LIST,该变量包含make所需要处理的makefile文件列表，当前makefile的文件名总是位于列表的最后，文件名之间以空格进行分隔，如下面include指令处理的文件
  $(eval include $(2))  #包含体现导入节点的makefile文件$(2)，包含的makefile文件里面会使用函数inherit-product来继承所有变量
  $(eval _included := $(filter-out $(2),$(MAKEFILE_LIST))) #过滤掉$(2)makefile，剩下其余的:也就是说$(2)makefile里面递归包含的
  $(eval MAKEFILE_LIST :=)  #使用后，清空变量MAKEFILE_LIST
  $(eval LOCAL_PATH :=)  #使用后，清空变量LOCAL_PATH
  $(call copy-var-list, $(1).$(2), $(3))  
  #拷贝变量列表：$(1).$(2)=_nic.PRODUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]].device/friendly-arm/tiny4412/full_tiny4412.mk
  #   PREFIX.$(3) := $( $(3) )
  $(call clear-var-list, $(3))  #使用后， 清除变量列表$(3)

  $(eval $(1).$(2).inherited := \
      $(call get-inherited-nodes,$(1).$(2),$(3))) 
  #  从 _nic.PRODUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]].device/friendly-arm/tiny4412/full_tiny4412.mk.$(3)变量里面获取继承节点
  #  将继承的节点的得到后复制给_nic.PRODUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]].device/friendly-arm/tiny4412/full_tiny4412.mk.inherited
  $(call _import-nodes-inner,$(1),$($(1).$(2).inherited),$(3))  #导入继承的节点，×××递归调用×××

  $(call _expand-inherited-values,$(1),$(2),$(3)) #跳出递归，将导入的节点换成具体的值。。。

  $(eval $(1).$(2).inherited :=) #清空_nic.PRO  DUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]].device/friendly-arm/tiny4412/full_tiny4412.mk.inherited变量
  $(eval _include_stack := $(wordlist 2,9999,$$(_include_stack)))  #取_include_stack的第2个到第9999个word更新到_include_stack,删除第一个mk，与第一句对应（添加第一个）
endef

#
# This will generate a warning for _included above
#  $(if $(_included), \
#      $(eval $(warning product spec file: $(2)))\
#      $(foreach _inc,$(_included),$(eval $(warning $(space)$(space)$(space)includes: $(_inc)))),)
#

#
# $(1): context prefix  #内容前缀：如 _nic.PRODUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]]
# $(2): list of makefiles representing nodes to import   # 下同， 如device/friendly-arm/tiny4412/full_tiny4412.mk
# $(3): list of node variable names  # 下同
#
#TODO: Make the "does not exist" message more helpful;
#      should print out the name of the file trying to include it.
define _import-nodes-inner
  $(foreach _in,$(2), \
    $(if $(wildcard $(_in)), \ # wildcard扩展通配符
      $(if $($(1).$(_in).seen), \ # 检查_nic.PRODUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]].device/friendly-arm/tiny4412/full_tiny4412.mk.seen变量是否为空
        $(eval ### "skipping already-imported $(_in)") \  # 如果不为空或者说已设置，那么打印一句log
       , \
        $(eval $(1).$(_in).seen := true) \  #如果没有导入，先设置一个标记变量，并将该变量设为true,
        $(call _import-node,$(1),$(strip $(_in)),$(3)) \ # 执行实际的导入
       ) \
     , \
      $(error $(1): "$(_in)" does not exist) \ #wildcard扩展_in后为空，打印错误log
     ) \
   )
endef

#
# $(1): output list variable name, like "PRODUCTS" or "DEVICES" # 输出列表变量名,如： PRODUCTS, DEVICES
# $(2): list of makefiles representing nodes to import # 表示要导入的节点的 makefile 列表 ,mk文件列表,如device/friendly-arm/tiny4412/full_tiny4412.mk
# $(3): list of node variable names  # 节点变量名称列表
#
define import-nodes
$(if \
  $(foreach _in,$(2), \
    $(eval _node_import_context := _nic.$(1).[[$(_in)]]) \  #导入内容的节点： _nic.PRODUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]]
    $(if $(_include_stack),$(eval $(error ASSERTION FAILED: _include_stack \
                should be empty here: $(_include_stack))),) \  # _include_stack变量此时应该为空，不为空会报错
    $(eval _include_stack := ) \  #清空_include_stack变量，因为该变量接下来会用到
    $(call _import-nodes-inner,$(_node_import_context),$(_in),$(3)) \  #调用内部的import-nodes函数来进行导入节点
    $(call move-var-list,$(_node_import_context).$(_in),$(1).$(_in),$(3)) \ 
    # src:_nic.PRODUCTS.[[device/friendly-arm/tiny4412/full_tiny4412.mk]].device/friendly-arm/tiny4412/full_tiny4412.mk   
    # dst:PRODUCTS.device/friendly-arm/tiny4412/full_tiny4412.mk
    #   DST.$(3) := $(SRC.$(3))
    #   SRC.$(3) :=
    $(eval $(1) := $($(1)) $(_in)) \  PRODUCTS := $(PRODUCTS) device/friendly-arm/tiny4412/full_tiny4412.mk
    $(if $(_include_stack),$(eval $(error ASSERTION FAILED: _include_stack \
                should be empty here: $(_include_stack))),) \
   ) \
,)
endef